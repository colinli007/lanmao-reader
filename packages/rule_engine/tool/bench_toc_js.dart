// 大目录耗时：每章的章节名、地址都有 JS，再加 formatJs，测目录链路（不联网，响应由内存提供）。
//
//   export QUICKJS_NG_FFI_LIB=$PWD/../quickjs_ng_ffi/build/host/libquickjs_ng_ffi.dylib
//   dart run tool/bench_toc_js.dart [章节数，默认 2000]
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:rule_engine/rule_engine.dart';
import 'package:rule_engine/src/host/cookie_store.dart';

void main(List<String> args) {
  final count = args.isEmpty ? 2000 : int.parse(args.single);
  final html = [for (var i = 1; i <= count; i++) '<li><a href="/c/$i.html"> 第$i章 标题$i </a></li>'].join();
  final env = _MemoryEnvironment({'https://a.com/toc': '<ul>$html</ul>'});
  final variants = {
    '纯规则': {'chapterList': 'tag.li', 'chapterName': 'tag.a@text', 'chapterUrl': 'tag.a@href'},
    '章节名和地址都有 JS': {
      'chapterList': 'tag.li',
      'chapterName': 'tag.a@text@js:result.trim()',
      'chapterUrl': "tag.a@href@js:result.replace('.html', '') + '.html'",
    },
    '再加 formatJs': {
      'chapterList': 'tag.li',
      'chapterName': 'tag.a@text@js:result.trim()',
      'chapterUrl': "tag.a@href@js:result.replace('.html', '') + '.html'",
      'formatJs': "index + '. ' + title",
    },
  };
  for (final MapEntry(key: name, value: toc) in variants.entries) {
    final source = loadBookSources(jsonEncode({'bookSourceUrl': 'https://a.com', 'bookSourceName': 'bench', 'ruleToc': toc})).sources.single;
    final book = Book.of(source, 'https://a.com/b')..tocUrl = 'https://a.com/toc';
    getChapterList(env, source, book); // 预热
    final watch = Stopwatch()..start();
    final chapters = getChapterList(env, source, book);
    print('$name：$count 章，${watch.elapsedMilliseconds} ms（${chapters.first.title} … ${chapters.last.title}）');
  }
  env.dispose();
}

final class _MemoryEnvironment implements RuleEnvironment {
  _MemoryEnvironment(this._pages);

  final Map<String, String> _pages;
  final MemorySourceStore _store = MemorySourceStore();
  final CookieStore _cookies = CookieStore();

  @override
  final Pointer<Int32> abortSignal = calloc<Int32>();

  void dispose() => calloc.free(abortSignal);

  @override
  HttpResult fetch(HttpRequest request) =>
      HttpResult(statusCode: 200, url: request.url, body: Uint8List.fromList(utf8.encode(_pages[request.url] ?? '')));

  @override
  List<HttpResult> fetchAll(List<HttpRequest> requests) => [for (final r in requests) fetch(r)];

  @override
  Object? store(StoreRequest request) => runStoreRequest(request, _store, _cookies);

  @override
  void log(SourceLog log) {}

  @override
  void checkCancelled() {}
}
