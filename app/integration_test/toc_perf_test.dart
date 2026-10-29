// 2000 章目录的打开耗时（prepare-release 设计 D6、任务 6.3，profile 构建）：
//   flutter drive --profile --driver=test_driver/integration_test.dart --target=integration_test/toc_perf_test.dart -d <设备>
// 一本 2000 章的书读到第 1501 章，只缓存这一章的正文，不联网。量两个入口：
// - 阅读页菜单里的「目录」：点下去到目录页里当前章那一行出现在屏幕上；
// - 书架打开的详情页：打开详情页（从数据库读 2000 行目录）到「共 2000 章」出现，再点它到目录页里当前章那一行出现在屏幕上。
// 目录页是 redesign-minimal-ui 设计 D4 的独立页面，阅读页和详情页共用。
// 每项先预热一次，再测 10 次，结果以 REPORT 开头打印。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:novel_reader/online/book_detail_page.dart';
import 'package:novel_reader/online/startup.dart';
import 'package:novel_reader/reader/reader_page.dart';
import 'package:novel_reader/reader/toc_page.dart';
import 'package:novel_reader/storage/database.dart';
import 'package:novel_reader/ui/theme.dart';

const _bookUrl = 'local://toc';
const _chapters = 2000;
const _current = 1500;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('$_chapters 章目录', (tester) async {
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    final db = AppDatabase(NativeDatabase.memory());
    await db.saveBrowsingBook(
      const ShelfBook(
        bookUrl: _bookUrl,
        origin: 'local://',
        originName: '本地',
        name: '长目录',
        author: '测试',
        durChapterIndex: _current,
        durChapterUrl: '/$_current',
        durChapterTitle: '第${_current + 1}章',
        durChapterPos: 0,
        inShelf: false,
        sourceData: '{}',
      ),
      [
        for (var i = 0; i < _chapters; i++)
          TocChapter(
            bookUrl: _bookUrl,
            idx: i,
            url: '/$i',
            title: '第${i + 1}章',
            isVolume: false,
            isVip: false,
            isPay: false,
            sourceData: '{}',
          ),
      ],
    );
    await db.addToShelf(_bookUrl, DateTime(2026));
    await db.putContent(
      ContentRow(
        bookUrl: _bookUrl,
        chapterUrl: '/$_current',
        title: '第${_current + 1}章',
        content: List.filled(40, '山风从谷底卷上来，吹得崖边的松枝簌簌作响。').join('\n'),
      ),
    );

    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: await startServices(database: db),
        child: MaterialApp(navigatorKey: navigator, theme: appTheme(Brightness.light), darkTheme: appTheme(Brightness.dark), home: const SizedBox()),
      ),
    );
    final size = tester.getSize(find.byType(MaterialApp));

    /// 从现在起，等到 [finder] 出现在屏幕上（能点到），返回毫秒数。
    Future<double> until(Finder finder) async {
      final watch = Stopwatch()..start();
      while (finder.hitTestable().evaluate().isEmpty) {
        if (watch.elapsed > const Duration(seconds: 10)) fail('10 秒内没有等到 $finder');
        await tester.pump(const Duration(milliseconds: 5));
      }
      return watch.elapsedMicroseconds / 1000;
    }

    final current = find.descendant(of: find.byType(TocPage), matching: find.text('第${_current + 1}章'));
    final reader = <double>[], detail = <double>[], detailToc = <double>[];

    /// 当前章在目录页里用强调色加粗标出。
    void expectMarked() => expect(tester.widget<Text>(current).style?.fontWeight, FontWeight.w600);

    // 阅读页的目录：每次打开再返回，菜单被收起时先点中间打开
    navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => const ReaderPage(bookUrl: _bookUrl)));
    await tester.pump(const Duration(seconds: 2));
    for (var i = 0; i <= 10; i++) {
      if (find.byTooltip('目录').hitTestable().evaluate().isEmpty) {
        await tester.tapAt(size.center(Offset.zero));
        await tester.pump(const Duration(milliseconds: 500));
      }
      await tester.tap(find.byTooltip('目录'));
      final ms = await until(current);
      if (i > 0) reader.add(ms);
      expectMarked();
      await tester.pump(const Duration(milliseconds: 500));
      navigator.currentState!.pop();
      await tester.pump(const Duration(milliseconds: 500));
    }
    navigator.currentState!.pop();
    await tester.pump(const Duration(seconds: 1));

    // 书架打开的详情页，再从详情页打开目录页
    final tocEntry = find.text('共 $_chapters 章');
    for (var i = 0; i <= 10; i++) {
      navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => const BookDetailPage.shelf(_bookUrl)));
      final open = await until(tocEntry);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(tocEntry);
      final list = await until(current);
      if (i > 0) {
        detail.add(open);
        detailToc.add(list);
      }
      expectMarked();
      navigator.currentState!
        ..pop()
        ..pop();
      await tester.pump(const Duration(seconds: 1));
    }

    double median(List<double> values) {
      final sorted = [...values]..sort();
      return (sorted[4] + sorted[5]) / 2;
    }

    String stats(List<double> values) => '中位数 ${median(values).toStringAsFixed(1)}ms，最大 ${([...values]..sort()).last.toStringAsFixed(1)}ms';
    debugPrint('REPORT 屏幕 ${size.width.toStringAsFixed(0)}×${size.height.toStringAsFixed(0)}');
    debugPrint('REPORT 阅读页点「目录」到第 ${_current + 1} 章出现：${stats(reader)}');
    debugPrint('REPORT 打开详情页到「共 $_chapters 章」出现：${stats(detail)}');
    debugPrint('REPORT 详情页点「目录」到第 ${_current + 1} 章出现：${stats(detailToc)}');
    expect([median(reader), median(detail), median(detailToc)], everyElement(lessThanOrEqualTo(1000)));
  });
}
