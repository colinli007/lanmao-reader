import 'dart:collection';
import 'dart:convert';

import 'package:quickjs_ng_ffi/quickjs_ng_ffi.dart';

import '../chain/models.dart';
import '../core/errors.dart';
import '../core/source_task.dart';
import '../request/analyze_url.dart';
import '../rule/analyze_rule.dart';
import '../rule/rule_data.dart';
import '../source/book_source.dart';
import 'codec.dart';
import 'crypto.dart' as crypto;
import 'host_api.dart';
import 'js_values.dart';
import 'prelude.dart';

/// 书源 JS 运行时：每个 isolate 一个引擎（worker 里一次只执行一个任务），规则引擎所有进入 JS 的地方都走这里。
///
/// - 每次求值用新的变量层（隔离作用域），注入本次的变量；书源有 jsLib 时挂上它的共享作用域。
/// - 宿主 API 只注册一个 `__host.call`，按「求值帧栈」的栈顶分发：规则、URL、书源三种上下文的 `java` 语义不同。
/// - 嵌套求值（JS 调回调规则，回调规则里又有 JS）最多 [maxDepth] 层，超过时以不可捕获的错误结束。
/// - 不支持的宿主 API、需要 WebView 等错误在 JS 里不可捕获，最外层求值还原成原来的错误类型。
final class SourceJs {
  SourceJs._() {
    engine.register('__host.call', _dispatch);
    engine.eval(sourceJsPrelude, filename: '<prelude>');
  }

  static SourceJs? _instance;

  /// 本 isolate 的运行时，第一次用到时创建。
  static SourceJs get instance => _instance ??= SourceJs._();

  static const int maxDepth = 10;

  /// 同一个 isolate 里缓存的 jsLib 个数（与 MD3 的 SharedJsScope 相同）。
  static const int maxLibs = 16;

  final JsEngine engine = JsEngine();
  final List<JsFrame> _frames = [];

  /// 不可捕获的错误的原样：抛到 JS 时只能带消息，最外层求值时还原它。
  RuleEngineException? _fatal;

  /// jsLib 的 MD5 → 共享作用域，按最近使用排序。
  final LinkedHashMap<String, JsLib> _libs = LinkedHashMap();

  /// 当前求值帧（宿主 API 的上下文）。
  JsFrame get currentFrame => _frames.last;

  // ---------------------------------------------------------------- 进入点

  /// 规则里的 JS 段和 `{{JS}}`：`java` 是规则上下文。
  Object? evalRule(AnalyzeRule rule, String code, {Object? result}) {
    final frame = RuleFrame(rule);
    final chapter = rule.chapter;
    return _run(frame, code, {
      'java': _hostObject('ruleJava'),
      'cookie': _hostObject('cookie'),
      'cache': _hostObject('cache'),
      'source': _sourceTag(rule.task),
      'book': rule.book,
      'result': result,
      'baseUrl': rule.baseUrl,
      'chapter': chapter,
      'title': chapter?.title,
      'src': rule.content,
      'nextChapterUrl': rule.nextChapterUrl,
    });
  }

  /// URL 里的 `@js:`、`<js>`、`{{}}`，选项 `js`、`bodyJs`，以及 `loginCheckJs`：`java` 是 URL 上下文。
  Object? evalUrl(SourceRequest request, String code, {Object? result}) {
    final frame = UrlFrame(request);
    return _run(frame, code, {
      'java': _hostObject('urlJava'),
      'cookie': _hostObject('cookie'),
      'cache': _hostObject('cache'),
      'source': _sourceTag(request.task),
      'book': request.book,
      'result': result,
      'baseUrl': request.baseUrl,
      'key': request.key,
      'page': request.page,
    });
  }

  /// 书源级 JS（书源 `header`）：`java` 是书源对象本身。
  Object? evalSource(SourceTask task, String code) {
    final source = _sourceTag(task);
    return _run(SourceFrame(task), code, {
      'java': source,
      'source': source,
      'baseUrl': task.sourceKey,
      'cookie': _hostObject('cookie'),
      'cache': _hostObject('cache'),
    });
  }

  /// 目录的 `formatJs`：所有章节共用一个变量层，`gInt` 和未声明的变量在章节之间累积；不注入 `java`、`source`、`book`，
  /// 也不挂 jsLib。返回值不为 null 时作为章节名。某一章出错时只记日志，章节名不变。
  void formatChapterTitles(SourceTask task, String code, List<BookChapter> chapters) {
    final layer = JsLayer(engine);
    try {
      for (final (index, chapter) in chapters.indexed) {
        task.env.checkCancelled();
        try {
          final value = _run(
            FormatFrame(task, chapter),
            code,
            {if (index == 0) 'gInt': 0, 'index': index + 1, 'chapter': chapter, 'title': chapter.title},
            layer: layer,
            withLib: false,
          );
          if (value != null) chapter.title = valueToString(value);
        } on JsEvalException catch (e) {
          task.log('格式化标题出错, ${e.message}');
        }
      }
    } finally {
      layer.dispose();
    }
  }

  // ---------------------------------------------------------------- 求值

  Object? _run(JsFrame frame, String code, Map<String, Object?> vars, {JsLayer? layer, bool withLib = true}) {
    final task = frame.task;
    if (_frames.length >= maxDepth) throw _raise(JsEvalException('嵌套求值超过 $maxDepth 层'));
    final lib = withLib ? _lib(task) : null;
    final encoded = {for (final MapEntry(:key, :value) in vars.entries) key: _toJs(frame, value)};
    final scope = layer ?? JsLayer(engine);
    _frames.add(frame);
    try {
      final json = engine.evalScoped(code, layer: scope, lib: lib, vars: encoded, abortSignal: task.env.abortSignal);
      return _fromJs(frame, json);
    } on JsException catch (e) {
      throw _jsError(e, task);
    } finally {
      _frames.removeLast();
      if (layer == null) scope.dispose();
    }
  }

  /// 不可捕获的错误：在最外层直接抛出 [error]；在嵌套求值里记下它，抛不可捕获的 JS 异常穿过外层 JS。
  Exception _raise(RuleEngineException error) {
    if (_frames.isEmpty) return error;
    _fatal = error;
    return JsException(error.toString(), uncatchable: true);
  }

  Exception _jsError(JsException e, SourceTask task) {
    final outermost = _frames.length == 1;
    if (e.uncatchable) {
      // 嵌套求值里原样往外传，直到最外层
      if (!outermost) return e;
      final fatal = _fatal;
      _fatal = null;
      if (fatal != null) return fatal;
      // 中止：任务被取消或超时，抛出对应的错误
      task.env.checkCancelled();
      return JsEvalException(_firstLine(e.message));
    }
    return JsEvalException(_firstLine(e.message));
  }

  static String _firstLine(String message) {
    final index = message.indexOf('\n');
    return index < 0 ? message : message.substring(0, index);
  }

  /// 书源的 jsLib：按全文的 MD5 缓存。JSON 形式（按地址引用外部脚本）不支持；执行出错时不缓存。
  JsLib? _lib(SourceTask task) {
    final code = task.source.jsLib;
    if (code == null || code.trim().isEmpty) return null;
    final trimmed = code.trim();
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) throw _raise(NeedsJsException('不支持的 jsLib 形式'));
    final key = hexEncode(crypto.digest('MD5', utf8.encode(code)));
    final cached = _libs.remove(key);
    if (cached != null) return _libs[key] = cached;
    try {
      final lib = JsLib(engine, code, abortSignal: task.env.abortSignal);
      _libs[key] = lib;
      if (_libs.length > maxLibs) _libs.remove(_libs.keys.first)!.dispose();
      return lib;
    } on JsException catch (e) {
      if (e.uncatchable) {
        task.env.checkCancelled();
        if (_frames.isNotEmpty) rethrow;
      }
      throw _raise(JsEvalException('jsLib 执行出错：${_firstLine(e.message)}'));
    }
  }

  // ---------------------------------------------------------------- 值

  static Map<String, Object?> _hostObject(String kind) => {hostObjectTag: kind};

  static Map<String, Object?> _sourceTag(SourceTask task) => {hostObjectTag: 'source', 'id': task.handles.add(task.source)};

  /// 书源对象的字段：书源 JSON 的全部字段。
  static Map<String, Object?> sourceFields(BookSource source) => source.json;

  Object? _toJs(JsFrame frame, Object? value) => toJsValue(value, frame.task.handles, hostObject: (value) {
    return switch (value) {
      Map<String, Object?>() when value.containsKey(hostObjectTag) => value,
      Book() || SearchBook() => {hostObjectTag: 'book', 'v': bookFields(value as BookData)},
      BookChapter() => {hostObjectTag: 'chapter', 'v': chapterFields(value)},
      JsObject() => null,
      _ => null,
    };
  });

  Object? _fromJs(JsFrame frame, Object? json) => fromJsValue(json, frame.task.handles, hostObject: (kind) {
    return switch (kind) {
      'book' => frame.book,
      'chapter' => frame.chapter,
      'source' => frame.task.source,
      _ => null,
    };
  });

  /// 宿主 API 的实参（JS 交来的 JSON）转成 Dart 值。
  Object? argFromJs(Object? json) => _fromJs(currentFrame, json);

  /// 宿主 API 的返回值转成交给 JS 的 JSON 值。
  Object? resultToJs(Object? value) => _toJs(currentFrame, value);

  // ---------------------------------------------------------------- 宿主 API 分发

  Object? _dispatch(List<Object?> args) {
    final api = args[0] as String;
    final callArgs = [for (final arg in args[1] as List) argFromJs(arg)];
    try {
      return resultToJs(callHostApi(this, currentFrame, api, callArgs));
    } on RuleEngineException catch (e) {
      if (isFatal(e)) throw _raise(e);
      rethrow;
    }
  }

  /// 在 JS 里不可捕获的错误：本引擎缺少的能力。JS 不能吞掉它们继续执行，否则会得到和 MD3 不同的结果。
  static bool isFatal(Object error) =>
      error is UnsupportedHostApiException ||
      error is NeedsWebViewException ||
      error is NeedsJsException ||
      (error is JsException && error.uncatchable);
}

/// 一次求值的上下文：宿主 API 按它分发。
sealed class JsFrame {
  SourceTask get task;

  /// `book.*` 方法作用的书籍。
  BookData? get book;

  /// `chapter.*` 方法作用的章节。
  ChapterData? get chapter;
}

/// 规则里的 JS：`java` 是 [rule]。
final class RuleFrame implements JsFrame {
  RuleFrame(this.rule);

  final AnalyzeRule rule;

  @override
  SourceTask get task => rule.task;

  @override
  BookData? get book => rule.book;

  @override
  ChapterData? get chapter => rule.chapter;
}

/// URL 里的 JS：`java` 是 [request]。
final class UrlFrame implements JsFrame {
  UrlFrame(this.request);

  final SourceRequest request;

  @override
  SourceTask get task => request.task;

  @override
  BookData? get book => request.book;

  @override
  ChapterData? get chapter => request.chapter;
}

/// 书源级 JS：`java` 是书源对象。
final class SourceFrame implements JsFrame {
  SourceFrame(this.task);

  @override
  final SourceTask task;

  @override
  BookData? get book => null;

  @override
  ChapterData? get chapter => null;
}

/// 目录的 `formatJs`。
final class FormatFrame implements JsFrame {
  FormatFrame(this.task, this.chapter);

  @override
  final SourceTask task;

  @override
  final BookChapter chapter;

  @override
  BookData? get book => null;
}

/// 书籍交给 JS 的字段（MD3 Book / SearchBook 的同名属性）。
Map<String, Object?> bookFields(BookData book) => switch (book) {
  Book() => {
    'name': book.name,
    'author': book.author,
    'bookUrl': book.bookUrl,
    'tocUrl': book.tocUrl,
    'origin': book.origin,
    'originName': book.originName,
    'kind': book.kind,
    'coverUrl': book.coverUrl,
    'intro': book.intro,
    'customIntro': book.customIntro,
    'wordCount': book.wordCount,
    'latestChapterTitle': book.latestChapterTitle,
    'totalChapterNum': book.totalChapterNum,
    'durChapterIndex': book.durChapterIndex,
    'durChapterTitle': book.durChapterTitle,
    'canUpdate': true,
    'variable': jsonEncode(book.variables),
  },
  SearchBook() => {
    'name': book.name,
    'author': book.author,
    'bookUrl': book.bookUrl,
    'origin': book.origin,
    'originName': book.originName,
    'kind': book.kind,
    'coverUrl': book.coverUrl,
    'intro': book.intro,
    'wordCount': book.wordCount,
    'latestChapterTitle': book.latestChapterTitle,
    'variable': jsonEncode(book.variables),
  },
  _ => {'name': book.name, 'variable': jsonEncode(book.variables)},
};

/// 章节交给 JS 的字段（MD3 BookChapter 的同名属性）。
Map<String, Object?> chapterFields(BookChapter chapter) => {
  'title': chapter.title,
  'url': chapter.url,
  'index': chapter.index,
  'isVolume': chapter.isVolume,
  'isVip': chapter.isVip,
  'isPay': chapter.isPay,
  'tag': chapter.tag,
  'baseUrl': chapter.baseUrl,
  'bookUrl': chapter.bookUrl,
  'variable': jsonEncode(chapter.variables),
};

/// JS 的值转成文本（MD3 里 `toString()` 的去处）：null 为 null，其余按 JS 的 `String()`，元素按 jsoup 的 `toString`。
String valueToString(Object value) => jsString(value);
