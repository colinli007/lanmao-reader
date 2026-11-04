import 'dart:async';

import 'package:blocking_bridge/blocking_bridge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanmao_reader/online/source_check.dart';
import 'package:lanmao_reader/online/source_repository.dart';
import 'package:rule_engine/rule_engine.dart';

import '../support/test_app.dart';

void main() {
  group('markCheckResult', () {
    const network = (kind: CheckInvalid.site, reason: '网络错误：连接被关闭');

    test('失败后标上分组和注释；再次通过时还原', () {
      final original = {'bookSourceUrl': 'A', 'bookSourceGroup': '常用', 'bookSourceComment': '作者：甲'};
      final failed = markCheckResult(original, network);
      expect(failed['bookSourceGroup'], '常用,网站失效');
      expect(failed['bookSourceComment'], '// Error: 网络错误：连接被关闭\n\n作者：甲');
      expect(markCheckResult(failed, null), original);
    });

    test('原来没有这两个字段：失败时加上，通过时去掉；没有标记要改时原样返回', () {
      final failed = markCheckResult({'bookSourceUrl': 'A'}, (kind: CheckInvalid.searchEmpty, reason: '搜索失效'));
      expect((failed['bookSourceGroup'], failed['bookSourceComment']), ('搜索失效', '// Error: 搜索失效'));
      expect(markCheckResult(failed, null), {'bookSourceUrl': 'A'});
      final untouched = {'bookSourceUrl': 'A', 'bookSourceGroup': ' 甲 ；乙', 'bookSourceComment': ''};
      expect(markCheckResult(untouched, null), untouched);
    });

    test('去掉所有旧的失效分组和错误注释，其余的顺序不变，同一个失效分组不重复', () {
      final marked = markCheckResult({
        'bookSourceUrl': 'A',
        'bookSourceGroup': '甲,搜索失效;乙，校验超时,js失效',
        'bookSourceComment': '第一段\n\n// Error: 旧的\n\n第二段',
      }, (kind: CheckInvalid.searchEmpty, reason: '搜索失效'));
      expect(marked['bookSourceGroup'], '甲,乙,搜索失效');
      expect(marked['bookSourceComment'], '// Error: 搜索失效\n\n第一段\n\n第二段');
    });
  });

  group('SourceCheckController', () {
    late TestServices services;
    late ProviderContainer container;

    Future<void> setUpWith({Duration timeout = const Duration(seconds: 180)}) async {
      services = await TestServices.create();
      container = ProviderContainer(
        overrides: [...services.overrides, sourceCheckProvider.overrideWith(() => SourceCheckController(timeout: timeout))],
      );
      container.listen(sourceCheckProvider, (_, _) {});
    }

    tearDown(() async {
      container.dispose();
      await services.db.close();
    });

    SourceCheckController controller() => container.read(sourceCheckProvider.notifier);
    SourceCheckState state() => container.read(sourceCheckProvider);
    List<BookSource> sources() => [for (final entry in services.repository.entries) entry.source];
    Map<String, Object?> json(String url) => services.repository[url]!.source.json;

    /// 校验全部书源并等它结束。
    Future<void> checkAll({String keyword = '我的'}) async {
      expect(controller().start(sources(), keyword), isTrue);
      while (state().running) {
        await pumpEventQueue();
      }
    }

    test('四步都通过：依次搜索、详情、目录、第一个不是卷名的章节，都按批量任务提交；书源不改', () async {
      await setUpWith();
      await services.useSimpleBook();
      services.engine.onChapterList = (source, book) async => (
        book: book,
        chapters: [
          BookChapter(bookUrl: book.bookUrl, baseUrl: book.bookUrl)
            ..title = '第一卷'
            ..url = '/v'
            ..isVolume = true,
          for (final i in [1, 2])
            BookChapter(bookUrl: book.bookUrl, baseUrl: book.bookUrl)
              ..title = '第$i章'
              ..url = '/$i.html',
        ],
      );
      String? next;
      final content = services.engine.onContent!;
      services.engine.onContent = (source, book, chapter, nextUrl) {
        next = nextUrl;
        return content(source, book, chapter, nextUrl);
      };
      final before = json(SimpleBook.sourceUrl);
      await checkAll();
      expect(services.engine.calls, ['search ${SimpleBook.sourceUrl}', 'info ${SimpleBook.bookUrl}', 'toc ${SimpleBook.bookUrl}', 'content /1.html']);
      expect(next, 'https://a.com/2.html');
      expect(services.engine.batches, hasLength(4));
      expect((state().done, state().total, state().invalid), (1, 1, 0));
      expect(json(SimpleBook.sourceUrl), before);
    });

    test('每一步的失败按 Legado 归类，写回分组和注释，位置和启用状态不变，重启后还在', () async {
      await setUpWith();
      await services.addSources([
        for (final name in ['net', 'js', 'api', 'toc', 'volume', 'content', 'empty', 'rule'])
          {'bookSourceUrl': name, 'searchUrl': '/s', if (name == 'js') 'enabled': false},
        {'bookSourceUrl': 'none', 'searchUrl': ' '},
      ]);
      BookChapter chapter(Book book, {bool volume = false}) => BookChapter(bookUrl: book.bookUrl, baseUrl: book.bookUrl)
        ..title = '第一章'
        ..url = '/1'
        ..isVolume = volume;
      services.engine
        ..onSearch = ((source, key) async => switch (source.bookSourceUrl) {
          'net' => throw HostCallException('连接被关闭'),
          'js' => throw JsEvalException('x is not defined'),
          'api' => throw UnsupportedHostApiException('java.webView'),
          'empty' => const [],
          _ => [SearchBook(bookUrl: '${source.bookSourceUrl}/b', origin: source.bookSourceUrl, originName: '')..name = '书'],
        })
        ..onBookInfo = ((source, b) async => b)
        ..onChapterList = ((source, b) async => switch (source.bookSourceUrl) {
          'toc' => throw RuleException(RuleException.tocEmpty),
          'volume' => (book: b, chapters: [chapter(b, volume: true)]),
          'rule' => throw RuleException('JSONPath 取不到值：data'),
          _ => (book: b, chapters: [chapter(b)]),
        })
        ..onContent = ((source, b, c, next) async => throw RuleException(RuleException.contentEmpty));
      final positions = [for (final entry in services.repository.entries) entry.url];
      await checkAll();

      String marks(String url) => '${json(url)['bookSourceGroup']} | ${json(url)['bookSourceComment']}';
      expect(marks('net'), '网站失效 | // Error: 网络错误：连接被关闭');
      expect(marks('js'), startsWith('js失效 | // Error: JS 错误：x is not defined'));
      expect(marks('api'), startsWith('js失效 | // Error: 不支持的宿主 API：java.webView'));
      expect(marks('toc'), '搜索目录失效 | // Error: 搜索目录失效');
      expect(marks('volume'), '搜索目录失效 | // Error: 搜索目录失效');
      expect(marks('content'), '搜索正文失效 | // Error: 搜索正文失效');
      expect(marks('empty'), '搜索失效 | // Error: 搜索失效');
      expect(marks('rule'), startsWith('网站失效 | // Error: 规则错误：JSONPath 取不到值：data'));
      expect(marks('none'), '搜索链接规则为空 | // Error: 搜索链接规则为空');
      expect(services.engine.calls, isNot(contains('search none')));
      expect((state().done, state().invalid), (9, 8));
      expect([for (final entry in services.repository.entries) entry.url], positions);
      expect(services.repository['js']!.enabled, isFalse);

      final reloaded = await SourceRepository.load(services.db);
      expect(reloaded['net']!.source.json['bookSourceGroup'], '网站失效');
    });

    test('文件类书源查到详情为止', () async {
      await setUpWith();
      await services.useSimpleBook();
      await services.addSources([{'bookSourceUrl': SimpleBook.sourceUrl, 'searchUrl': '/s', 'bookSourceType': 3}]);
      await checkAll();
      expect(services.engine.calls, ['search ${SimpleBook.sourceUrl}', 'info ${SimpleBook.bookUrl}']);
      expect(state().invalid, 0);
    });

    test('关键词：书源自带的优先，含 http、::、++、-- 的不用', () async {
      await setUpWith();
      await services.addSources([
        {'bookSourceUrl': 'A', 'searchUrl': '/s', 'ruleSearch': {'checkKeyWord': '三体'}},
        {'bookSourceUrl': 'B', 'searchUrl': '/s'},
        {'bookSourceUrl': 'C', 'searchUrl': '/s', 'ruleSearch': {'checkKeyWord': 'http://x'}},
      ]);
      final keys = <String, String>{};
      services.engine.onSearch = (source, key) async {
        keys[source.bookSourceUrl] = key;
        return const [];
      };
      await checkAll(keyword: '斗破');
      expect(keys, {'A': '三体', 'B': '斗破', 'C': '斗破'});
    });

    test('超过时间记为校验超时', () async {
      await setUpWith(timeout: const Duration(milliseconds: 50));
      await services.addSources([{'bookSourceUrl': 'A', 'searchUrl': '/s'}]);
      services.engine.onSearch = (source, key) => Completer<List<SearchBook>>().future;
      await checkAll();
      expect(json('A')['bookSourceGroup'], '校验超时');
      expect(json('A')['bookSourceComment'], '// Error: 超时：超过 0 秒');
    });

    test('同时最多 16 个；进行中再发起被拒绝；停止后没完成的不改', () async {
      await setUpWith();
      await services.addSources([for (var i = 0; i < 20; i++) {'bookSourceUrl': 'S$i', 'searchUrl': '/s'}]);
      final pending = <String, Completer<List<SearchBook>>>{};
      services.engine.onSearch = (source, key) => (pending[source.bookSourceUrl] = Completer()).future;
      controller().start(sources(), '我的');
      await pumpEventQueue();
      expect(pending, hasLength(16));
      expect(controller().start(sources(), '我的'), isFalse);

      pending['S0']!.complete(const []);
      await pumpEventQueue();
      expect(pending, hasLength(17));
      expect((state().done, state().running), (1, true));

      controller().stop();
      for (final completer in pending.values) {
        if (!completer.isCompleted) completer.complete(const []);
      }
      await pumpEventQueue();
      expect((state().done, state().running), (1, false));
      expect(json('S0')['bookSourceGroup'], '搜索失效');
      expect([for (var i = 1; i < 20; i++) json('S$i')['bookSourceGroup']], everyElement(isNull));
      expect(pending, hasLength(17));
    });
  });
}
