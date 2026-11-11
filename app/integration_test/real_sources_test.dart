import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lanmao_reader/app.dart';
import 'package:lanmao_reader/online/book_detail_page.dart';
import 'package:lanmao_reader/online/search_controller.dart';
import 'package:lanmao_reader/online/search_page.dart';
import 'package:lanmao_reader/online/startup.dart';
import 'package:lanmao_reader/reader/reader_page.dart';
import 'package:lanmao_reader/settings/source_feature.dart';
import 'package:lanmao_reader/storage/database.dart';
import 'package:path_provider/path_provider.dart';

/// 真实书源走查（联网，结果取决于网站当时的状态，不进日常测试）：
///
/// ```bash
/// flutter test integration_test/real_sources_test.dart -d macos \
///   --dart-define=WALKTHROUGH_SOURCES=http://127.0.0.1:8765/recorded14.json \
///   --dart-define=BENCH_SOURCES=http://127.0.0.1:8765/random200.json
/// ```
///
/// 书源文件从网址导入（走「从网址导入」的界面）。走查：在 [_targets] 列出的 A、C 类书源上各走一遍
/// 详情 → 加入书架 → 读两章，然后像重启一样重新打开同一个数据库，从书架继续阅读并刷新书架。
/// 计时：在 200 个书源上搜索一次，报告总耗时、完成一半和九成书源时的耗时、失败原因的分布。报告以 `REPORT` 开头打印。
const _walkthroughSources = String.fromEnvironment('WALKTHROUGH_SOURCES');
const _benchSources = String.fromEnvironment('BENCH_SOURCES');
const _key = String.fromEnvironment('KEY', defaultValue: '斗罗大陆');

/// 冒烟时跑通过的书源：前三个是 A 类（只有规则），后三个是 C 类（JS 里调宿主 API）。
const _targets = [
  'http://www.biduju.net/',
  'https://www.douyinxs.com/',
  'http://m.rulianshi.la/',
  'https://www.dkmi.com/',
  'https://www.idejian.com',
  'https://wap.yingsx.com/',
];

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // 让测试接管文字输入通道：不接管时 enterText 用 -1 作输入连接编号，框架只在 debug 构建里（assert）放行它，
  // profile 构建会静默丢掉输入的文字。见 app_flow_test.dart
  binding.testTextInput.register();

  void report(String line) => debugPrint('REPORT $line');

  /// 封面 404 是网站的问题：图片在它的组件已经销毁之后才失败时，Flutter 会把它当成错误报告（app 里只打日志）。
  /// 走查期间忽略这类错误，测试结束前恢复。
  void ignoreCoverErrors() {
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exception is! NetworkImageLoadException) original?.call(details);
    };
    addTearDown(() => FlutterError.onError = original);
  }

  /// 关掉界面，等后台的预加载、落盘、封面请求都结束，再关数据库（真实的 app 不会在运行中关数据库）。
  Future<void> shutdown(WidgetTester tester, AppDatabase db) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 15)));
    await db.close();
  }

  Future<bool> pumpUntil(WidgetTester tester, bool Function() done, {required Duration timeout}) async {
    final end = DateTime.now().add(timeout);
    while (!done()) {
      if (DateTime.now().isAfter(end)) return false;
      await tester.pump(const Duration(milliseconds: 200));
    }
    return true;
  }

  Future<File> freshDatabase(String name) async {
    final file = File('${(await getTemporaryDirectory()).path}/$name.sqlite');
    if (file.existsSync()) file.deleteSync();
    return file;
  }

  Future<void> startApp(WidgetTester tester, AppDatabase db) async {
    // iOS 上书源功能默认关闭（关于页连点版本号打开），这里直接写成已打开
    await db.putSetting(SourceFeatureNotifier.unlockedKey, 'true');
    await tester.pumpWidget(
      ProviderScope(
        overrides: await startServices(database: db),
        child: const LanmaoReaderApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> importFromUrl(WidgetTester tester, String url) async {
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('书源'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('导入'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('从网址导入'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, url);
    await tester.tap(find.text('确定'));
    final previewed = await pumpUntil(
      tester,
      () => find.textContaining('新增').evaluate().isNotEmpty || find.text('无法导入').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 60),
    );
    expect(previewed && find.text('无法导入').evaluate().isEmpty, isTrue, reason: '导入预览没有出现');
    report('导入 $url：${(find.textContaining('新增').evaluate().single.widget as Text).data}');
    await tester.tap(find.text('导入').last);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('书架'));
    await tester.pumpAndSettle();
  }

  /// 搜索并等到结束，返回耗时。[onPump] 在每次 pump 之后拿到从开始搜索算起的时间。
  Future<Duration> search(WidgetTester tester, {void Function(Duration elapsed)? onPump}) async {
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), _key);
    final watch = Stopwatch()..start();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    final finished = await pumpUntil(tester, () {
      onPump?.call(watch.elapsed);
      return find.textContaining('搜索结束').evaluate().isNotEmpty;
    }, timeout: const Duration(minutes: 10));
    expect(finished, isTrue, reason: '搜索没有在 10 分钟内结束');
    return watch.elapsed;
  }

  SearchState searchState(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(SearchPage))).read(searchControllerProvider);

  /// 阅读页上显示的正文：正文是自己画的，每页（滚动模式是每段）带一个读屏标签。
  Finder readerParagraphs() => find.descendant(
    of: find.byType(ReaderPage),
    matching: find.byWidgetPredicate((w) => w is Semantics && (w.properties.label?.isNotEmpty ?? false)),
  );

  /// 正文显示出来了：有正文，并且不是加载中的页或失败的页。
  bool readerShown() =>
      readerParagraphs().evaluate().isNotEmpty &&
      find.text('重试').evaluate().isEmpty &&
      find.descendant(of: find.byType(ReaderPage), matching: find.byType(CircularProgressIndicator)).evaluate().isEmpty;

  testWidgets('在 200 个书源上搜索一次', (tester) async {
    ignoreCoverErrors();
    final db = AppDatabase(NativeDatabase(await freshDatabase('bench')));
    await startApp(tester, db);
    await importFromUrl(tester, _benchSources);
    // 每次 pump 记下完成数和失败数的变化，用来校准单书源的超时（设计 D7）
    Duration? half;
    Duration? ninety;
    var done = 0;
    var failed = 0;
    var lateOk = 0;
    var lateFailed = 0;
    final elapsed = await search(
      tester,
      onPump: (elapsed) {
        final state = searchState(tester);
        final newFailed = state.failures.length - failed;
        final newOk = state.done - done - newFailed;
        if (elapsed > const Duration(seconds: 30)) {
          lateOk += newOk;
          lateFailed += newFailed;
        }
        done = state.done;
        failed = state.failures.length;
        if (done > 0 && done * 2 >= state.total) half ??= elapsed;
        if (done > 0 && done * 10 >= state.total * 9) ninety ??= elapsed;
      },
    );
    final state = searchState(tester);
    final reasons = <String, int>{};
    for (final failure in state.failures) {
      final kind = failure.reason.split('：').first;
      reasons[kind] = (reasons[kind] ?? 0) + 1;
    }
    report(
      '搜索「$_key」${state.total} 个书源，耗时 ${elapsed.inSeconds} 秒，合并后 ${state.books.length} 本，'
      '有结果的书源 ${state.total - state.failures.length}（含 0 结果），失败 ${state.failures.length}：$reasons',
    );
    String seconds(Duration? d) => d == null ? '-' : (d.inMilliseconds / 1000).toStringAsFixed(1);
    report(
      '完成一半 ${seconds(half)} 秒，九成 ${seconds(ninety)} 秒，全部 ${seconds(elapsed)} 秒；'
      '30 秒以后完成的书源：成功 $lateOk，失败 $lateFailed',
    );
    await shutdown(tester, db);
  }, skip: _benchSources.isEmpty);

  testWidgets('A、C 类书源走查：详情 → 加书架 → 读两章 → 重启后继续 → 刷新书架', (tester) async {
    ignoreCoverErrors();
    final file = await freshDatabase('walkthrough');
    var db = AppDatabase(NativeDatabase(file));
    await startApp(tester, db);
    await importFromUrl(tester, _walkthroughSources);
    final elapsed = await search(tester);
    final state = searchState(tester);
    report('走查搜索 ${state.total} 个书源，耗时 ${elapsed.inSeconds} 秒，失败：${[for (final f in state.failures) '${f.sourceName}=${f.reason}']}');

    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    final shelved = <String>[];
    for (final url in _targets) {
      final candidate = [
        for (final book in state.books)
          for (final result in book.results)
            if (result.source.url == url && book.name.contains(_key)) result,
      ].firstOrNull;
      if (candidate == null) {
        report('$url：搜索没有「$_key」的结果');
        continue;
      }
      final merged = MergedBook(candidate.book.name, candidate.book.author)..results.add(candidate);
      navigator.push(MaterialPageRoute<void>(builder: (_) => BookDetailPage.search(merged)));
      final tocLoaded = await pumpUntil(
        tester,
        () => find.textContaining(RegExp(r'^共 \d+ 章$')).evaluate().isNotEmpty || find.text('重试').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 90),
      );
      if (!tocLoaded || find.text('重试').evaluate().isNotEmpty) {
        final error = find
            .descendant(of: find.byType(BookDetailPage), matching: find.byType(Text))
            .evaluate()
            .map((e) => (e.widget as Text).data)
            .whereType<String>()
            .where((t) => t.contains('：'))
            .firstOrNull;
        report('${candidate.source.source.bookSourceName}：详情或目录失败 $error');
        navigator.pop();
        await tester.pumpAndSettle();
        continue;
      }
      await tester.tap(find.text('加入书架'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始阅读'));
      final first = await pumpUntil(
        tester,
        () => readerShown() || find.text('重试').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 90),
      );
      final firstOk = first && readerShown();
      var secondOk = false;
      if (firstOk) {
        // 默认是分页模式：从菜单的进度面板进下一章（窗口已经预加载过它）
        await tester.tapAt(tester.getCenter(find.byType(ReaderPage)));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('进度'));
        await tester.pumpAndSettle();
        final next = find.ancestor(of: find.byTooltip('下一章'), matching: find.byType(IconButton));
        if (tester.widget<IconButton>(next).onPressed != null) {
          await tester.tap(next);
          await tester.pump();
          secondOk = await pumpUntil(tester, readerShown, timeout: const Duration(seconds: 90));
        }
      }
      final chars = readerParagraphs().evaluate().fold(0, (sum, e) => sum + ((e.widget as Semantics).properties.label?.length ?? 0));
      report(
        '${candidate.source.source.bookSourceName}：《${candidate.book.name}》第一章 ${firstOk ? '通过' : '失败'}，第二章 ${secondOk ? '通过' : '失败'}（这一页 $chars 字）',
      );
      if (firstOk) shelved.add(candidate.book.bookUrl);
      navigator.pop(); // 阅读页
      await tester.pumpAndSettle();
      navigator.pop(); // 详情页
      await tester.pumpAndSettle();
    }
    expect(shelved, isNotEmpty, reason: '没有一个书源走通');

    // 重启：关掉 app 的界面和数据库，用同一个数据库文件重新启动
    await shutdown(tester, db);
    db = AppDatabase(NativeDatabase(file));
    await startApp(tester, db);
    final shelf = await db.shelf();
    report('重启后书架 ${shelf.length} 本：${[for (final e in shelf) '${e.book.name}@第${e.book.durChapterIndex + 1}章 未读${e.unread}']}');
    expect(shelf.map((e) => e.book.bookUrl).toSet(), shelved.toSet());

    // 从书架继续阅读：回到上次的章节，正文读缓存
    final book = shelf.first.book;
    await tester.tap(find.text(book.name).first);
    expect(await pumpUntil(tester, readerShown, timeout: const Duration(seconds: 30)), isTrue);
    final title = (await db.chaptersOf(book.bookUrl))[book.durChapterIndex].title;
    final shown = find.bySemanticsLabel(RegExp(RegExp.escape(title))).evaluate().isNotEmpty;
    report('从书架打开《${book.name}》：显示「$title」${shown ? '' : '（没找到章节名）'}');
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();

    // 刷新书架
    final watch = Stopwatch()..start();
    // macOS 上有「更新目录」按钮，手机上下拉
    if (find.byTooltip('更新目录').evaluate().isNotEmpty) {
      await tester.tap(find.byTooltip('更新目录'));
    } else {
      await tester.fling(find.byType(Scrollable).first, const Offset(0, 400), 1000);
    }
    await tester.pump();
    expect(await pumpUntil(tester, () => find.textContaining('正在更新目录').evaluate().isEmpty, timeout: const Duration(minutes: 3)), isTrue);
    final marks = find.textContaining('更新失败').evaluate().length + find.text('书源不存在').evaluate().length;
    report('刷新书架 ${shelf.length} 本，耗时 ${watch.elapsed.inSeconds} 秒，失败 $marks 本');
    await shutdown(tester, db);
  }, skip: _walkthroughSources.isEmpty);
}
