import 'dart:collection';

import 'package:quickjs_ng_ffi/quickjs_ng_ffi.dart';

import '../core/environment.dart';

/// 书源提供的正则（Java 语法），转换成 JS 语法后在 libregexp 里执行，匹配能被任务的中止信号打断。
///
/// 引擎自己写死的正则用 Dart [RegExp]，不走这里。
final class SourceRegex {
  SourceRegex._(this.pattern, this._regExp);

  /// 编译 Java 语法的正则，无法编译时返回 null（调用方按 MD3 的做法退化为字面量）。
  /// 编译结果按正则串缓存在当前 isolate 里，最多 [cacheSize] 条。
  static SourceRegex? tryCompile(String pattern) => _compile(pattern, entire: false);

  static SourceRegex? _compile(String pattern, {required bool entire}) {
    // 整串匹配用的正则另外编译，键前加一个正则里不会出现的字符区分
    final key = entire ? '\u0000$pattern' : pattern;
    if (_cache.containsKey(key)) {
      // 访问过的放回末尾；编译失败的也缓存，值为 null
      final cached = _cache.remove(key);
      _cache[key] = cached;
      return cached;
    }
    SourceRegex? compiled;
    try {
      final (source, flags) = translateJavaRegex(pattern);
      // 不用 ^ 和 \$：开了多行标志时它们也匹配行首行尾
      final body = entire ? '(?<![\\s\\S])(?:$source)(?![\\s\\S])' : source;
      compiled = SourceRegex._(
        pattern,
        JsRegExp(_engine, body, ignoreCase: flags.ignoreCase, multiLine: flags.multiLine, dotAll: flags.dotAll),
      );
    } on FormatException {
      compiled = null;
    }
    _cache[key] = compiled;
    if (_cache.length > cacheSize) {
      _cache.remove(_cache.keys.first)?._regExp.dispose();
    }
    return compiled;
  }

  /// 每个 isolate 缓存的正则条数上限。同一个书源的净化规则会被反复使用。
  static const int cacheSize = 256;

  // 正则只用引擎的分配器和中止检查，不执行 JS；每个 isolate 一个
  static final JsEngine _engine = JsEngine();
  static final LinkedHashMap<String, SourceRegex?> _cache = LinkedHashMap();

  /// 原始的 Java 语法正则。
  final String pattern;
  final JsRegExp _regExp;

  int get groupCount => _regExp.groupCount;

  int? groupIndex(String name) => _regExp.groupIndex(name);

  /// 从 [start] 开始查找第一个匹配。任务被取消时抛出取消错误。
  JsRegExpMatch? firstMatch(RuleEnvironment env, String input, {int start = 0}) =>
      _guard(env, () => _regExp.firstMatch(input, start: start, abortSignal: env.abortSignal));

  /// 全部不重叠的匹配。任务被取消时抛出取消错误。
  List<JsRegExpMatch> allMatches(RuleEnvironment env, String input) =>
      _guard(env, () => _regExp.allMatches(input, abortSignal: env.abortSignal));

  /// 整串匹配（Kotlin 的 `Regex.matches`）。
  bool matchesEntire(RuleEnvironment env, String input) =>
      _compile(pattern, entire: true)?.firstMatch(env, input) != null;

  T _guard<T>(RuleEnvironment env, T Function() body) {
    try {
      return body();
    } on JsException {
      // 中止导致的失败换成任务的取消错误；内存不足等其它失败照常抛出
      env.checkCancelled();
      rethrow;
    }
  }
}

/// Java 正则的开头内联标志。
typedef JavaRegexFlags = ({bool ignoreCase, bool multiLine, bool dotAll});

/// 把 Java 正则转成 libregexp 能编译的 JS 正则，只处理书源里实际出现的差异：
/// - 开头的内联标志 `(?i)`、`(?m)`、`(?s)`（及其组合）转成标志，`(?u)` 忽略；
/// - `\h`、`\H`（水平空白）换成等价的字符类；
/// - 占有量词（`*+`、`++`、`?+`、`{n,m}+`）降为普通贪婪量词；
/// - MD3 跑在 Android 上，`java.util.regex` 底层是 ICU：`\d` 是全部 Unicode 十进制数字（含全角数字），
///   `\w` 是 `[\p{Alphabetic}\p{M}\p{Nd}\p{Pc}\u200c\u200d]`（含汉字）。JS 里这两个只认 ASCII，所以换成等价的字符类
///   （限 BMP）；字符类里的 `\D`、`\W` 无法改写，保留 ASCII 语义。`\s` 两边基本一致，不改。
///
/// 其余写法原样保留，编译不了时调用方退化为字面量。
(String, JavaRegexFlags) translateJavaRegex(String pattern) {
  var ignoreCase = false;
  var multiLine = false;
  var dotAll = false;
  var start = 0;
  for (final match in _leadingFlags.allMatches(pattern)) {
    if (match.start != start) break;
    final flags = match.group(1)!;
    ignoreCase |= flags.contains('i');
    multiLine |= flags.contains('m');
    dotAll |= flags.contains('s');
    start = match.end;
  }

  final out = StringBuffer();
  var inClass = false;
  // 上一个输出的是量词，紧跟的 `+` 是占有量词的标记
  var afterQuantifier = false;
  var i = start;
  while (i < pattern.length) {
    final char = pattern[i];
    if (char == r'\' && i + 1 < pattern.length) {
      final next = pattern[i + 1];
      if (next == 'h') {
        out.write(inClass ? _horizontalSpace : '[$_horizontalSpace]');
      } else if (next == 'H' && !inClass) {
        out.write('[^$_horizontalSpace]');
      } else if (next == 'd' || next == 'w') {
        final body = next == 'd' ? _icuDigit : _icuWord;
        out.write(inClass ? body : '[$body]');
      } else if ((next == 'D' || next == 'W') && !inClass) {
        out.write('[^${next == 'D' ? _icuDigit : _icuWord}]');
      } else {
        out
          ..write(char)
          ..write(next);
      }
      i += 2;
      afterQuantifier = false;
      continue;
    }
    if (inClass) {
      if (char == ']') inClass = false;
      out.write(char);
      i++;
      continue;
    }
    if (afterQuantifier && char == '+') {
      afterQuantifier = false;
      i++;
      continue;
    }
    switch (char) {
      case '[':
        inClass = true;
        afterQuantifier = false;
      case '*' || '+':
        afterQuantifier = true;
      case '?':
        // `(?` 是分组语法，`*?` 这类是懒惰量词，都不是可以带占有标记的量词
        afterQuantifier = i > start && pattern[i - 1] != '(' && !afterQuantifier;
      case '{':
        final quantifier = _boundedQuantifier.matchAsPrefix(pattern, i);
        if (quantifier != null) {
          out.write(quantifier.group(0));
          i = quantifier.end;
          afterQuantifier = true;
          continue;
        }
        afterQuantifier = false;
      default:
        afterQuantifier = false;
    }
    out.write(char);
    i++;
  }
  return (out.toString(), (ignoreCase: ignoreCase, multiLine: multiLine, dotAll: dotAll));
}

final RegExp _leadingFlags = RegExp(r'\(\?([imsu]+)\)');
final RegExp _boundedQuantifier = RegExp(r'\{\d+(,\d*)?\}');

/// Java `\h` 的字符集合，不带方括号。
const String _horizontalSpace = r' \t  ᠎ -   　';

/// ICU 的 `\d`：Unicode 十进制数字，BMP 内的范围。
final String _icuDigit = _bmpRanges(RegExp(r'\p{Nd}', unicode: true));

/// ICU 的 `\w`。
final String _icuWord = _bmpRanges(RegExp(r'[\p{Alphabetic}\p{M}\p{Nd}\p{Pc}\u200c\u200d]', unicode: true));

/// 扫描 BMP（跳过代理区），把匹配 [property] 的字符写成字符类的内容，如 `\u0030-\u0039`。
String _bmpRanges(RegExp property) {
  final out = StringBuffer();
  String hex(int c) => '\\u${c.toRadixString(16).padLeft(4, '0')}';
  var start = -1;
  for (var c = 0; c <= 0x10000; c++) {
    final inRange = c < 0x10000 && (c < 0xD800 || c > 0xDFFF) && property.hasMatch(String.fromCharCode(c));
    if (inRange && start < 0) start = c;
    if (!inRange && start >= 0) {
      out.write(start == c - 1 ? hex(start) : '${hex(start)}-${hex(c - 1)}');
      start = -1;
    }
  }
  return out.toString();
}
