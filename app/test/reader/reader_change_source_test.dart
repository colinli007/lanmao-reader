import 'dart:async';

import 'package:blocking_bridge/blocking_bridge.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanmao_reader/online/change_source_page.dart';
import 'package:lanmao_reader/reader/paged/chapter_window.dart';
import 'package:lanmao_reader/reader/paged/paged_view.dart';
import 'package:lanmao_reader/reader/reader_page.dart';
import 'package:lanmao_reader/reader/reader_settings.dart';
import 'package:lanmao_reader/reader/scroll/scroll_view.dart';
import 'package:lanmao_reader/storage/database.dart';
import 'package:rule_engine/rule_engine.dart';

import '../support/test_app.dart';

void main() {
  const b = 'https://b.com';
  const c = 'https://c.com';
  const numerals = ['零', '一', '二', '三', '四', '五'];
  late TestServices services;
  late List<String> openedSources;

  setUp(() async {
    services = await TestServices.create();
    await services.useSimpleBook(chapters: 6, paragraphs: 80);
    await services.shelveSimpleBook(chapters: 6);
    await services.addSources([
      {'bookSourceUrl': b, 'bookSourceName': '书源乙', 'searchUrl': '/s'},
      {'bookSourceUrl': c, 'bookSourceName': '书源丙', 'searchUrl': '/s'},
    ]);
    openedSources = [];
    final original = (search: services.engine.onSearch!, info: services.engine.onBookInfo!, toc: services.engine.onChapterList!);
    services.engine
      ..onSearch = ((source, key) async => source.bookSourceUrl == SimpleBook.sourceUrl
          ? original.search(source, key)
          : [
              SearchBook(bookUrl: '${source.bookSourceUrl}/book/1', origin: source.bookSourceUrl, originName: source.bookSourceName)
                ..name = '三体'
                ..author = '刘慈欣',
            ])
      ..onBookInfo = ((source, book) => source.bookSourceUrl == SimpleBook.sourceUrl ? original.info(source, book) : Future.value(book))
      ..onChapterList = ((source, book) async {
        if (source.bookSourceUrl == SimpleBook.sourceUrl) return original.toc(source, book);
        return (
          book: book,
          chapters: [
            BookChapter(bookUrl: book.bookUrl, baseUrl: book.bookUrl)
              ..index = 0
              ..title = '正文卷'
              ..url = '/volume'
              ..isVolume = true,
            for (var i = 0; i < 6; i++)
              BookChapter(bookUrl: book.bookUrl, baseUrl: book.bookUrl)
                ..index = i + 1
                ..title = '第${numerals[i]}章'
                ..url = '/chapter-$i',
          ],
        );
      })
      ..onContent = ((source, book, chapter, next) async => ChapterContent(
        [for (var i = 0; i < 80; i++) '${source.bookSourceName}${chapter.title}第$i段，山风穿过林间，故事仍在继续。'].join('\n'),
        title: chapter.title,
      ));
  });
  tearDown(() => services.db.close());

  Future<void> open(WidgetTester tester, {PageMode mode = PageMode.none, int startAt = 3}) async {
    await tester.pumpWidget(
      services.app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ReaderPage(
                    bookUrl: SimpleBook.bookUrl,
                    startAt: startAt,
                    onChangeSource: (context, url) {
                      openedSources.add(url);
                      return Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => ChangeSourcePage(bookUrl: url)));
                    },
                  ),
                ),
              ),
              child: const Text('打开阅读'),
            ),
          ),
        ),
        overrides: [
          initialSettingsProvider.overrideWithValue(ReaderSettings(pageMode: mode, fontSize: 22, theme: ReaderTheme.sepia).toMap()),
        ],
      ),
    );
    await tester.tap(find.text('打开阅读'));
    await tester.pumpAndSettle();
  }

  ChapterWindow window(WidgetTester tester) => find.byType(PagedView).evaluate().isNotEmpty
      ? tester.widget<PagedView>(find.byType(PagedView)).window
      : tester.widget<ScrollReaderView>(find.byType(ScrollReaderView)).window;

  Future<void> showMenu(WidgetTester tester) async {
    if (find.byTooltip('换书源').evaluate().isEmpty) {
      await tester.tapAt(tester.getCenter(find.byType(ReaderPage)));
      await tester.pumpAndSettle();
    }
  }

  Future<void> choose(WidgetTester tester, String name) async {
    await showMenu(tester);
    await tester.tap(find.byTooltip('换书源'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
  }

  Future<void> leave(WidgetTester tester) async {
    await showMenu(tester);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('打开阅读'), findsOneWidget);
    expect(find.byType(ReaderPage), findsNothing);
  }

  testWidgets('防抖保存前换源：立即保存页内位置，按章节编号对齐并继续阅读', (tester) async {
    await open(tester);
    await tester.tapAt(const Offset(780, 300));
    await tester.pump();
    final before = window(tester);
    final offset = before.offset;
    expect(offset, greaterThan(0));
    expect((await services.db.getBook(SimpleBook.bookUrl))!.durChapterPos, 0, reason: '同章翻页的 2 秒防抖尚未落盘');

    await choose(tester, '书源乙');
    final after = window(tester);
    expect(identical(before, after), isFalse);
    expect((after.chapter, after.offset), (4, offset));
    expect(after.layoutOf(4)!.chapter.title, '第三章');
    expect(after.layoutOf(4)!.chapter.paragraphs.first.text, startsWith('书源乙'));
    final changed = (await services.db.getBook('$b/book/1'))!;
    expect((changed.inShelf, changed.durChapterIndex, changed.durChapterPos), (true, 4, offset));
    expect(await services.db.getBook(SimpleBook.bookUrl), isNull);
    expect(find.byType(ChangeSourcePage), findsNothing);
    expect(find.byType(ReaderPage), findsOneWidget);
    await leave(tester);
  });

  testWidgets('滚动模式换源保留设置和章内位置，仍显示滚动阅读', (tester) async {
    await open(tester, mode: PageMode.scroll);
    await tester.drag(find.byType(ScrollReaderView), const Offset(0, -900));
    await tester.pumpAndSettle();
    final offset = window(tester).offset;
    expect(offset, greaterThan(0));
    await choose(tester, '书源乙');
    expect(find.byType(ScrollReaderView), findsOneWidget);
    expect(find.byType(PagedView), findsNothing);
    expect(window(tester).chapter, 4);
    final settings = ProviderScope.containerOf(tester.element(find.byType(ReaderPage))).read(readerSettingsProvider);
    expect((settings.pageMode, settings.fontSize, settings.theme), (PageMode.scroll, 22, ReaderTheme.sepia));
    // 滚动定位后会把进度对齐到新字体排版的行首，与原字符位置最多相差一行。
    expect((window(tester).offset - offset).abs(), lessThan(50));
    expect(window(tester).layoutOf(4)!.chapter.paragraphs.first.text, startsWith('书源乙'));
    await leave(tester);
  });

  testWidgets('取消和候选加载失败都保留原阅读窗口，返回后还能翻页', (tester) async {
    await open(tester);
    final original = window(tester);
    await showMenu(tester);
    await tester.tap(find.byTooltip('换书源'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(window(tester), same(original));
    final chapterList = services.engine.onChapterList!;
    services.engine.onChapterList = (source, book) =>
        source.bookSourceUrl == b ? Future.error(const HostCallException('Connection refused')) : chapterList(source, book);
    await choose(tester, '书源乙');
    expect(find.text('网络错误：Connection refused'), findsOneWidget);
    expect(await services.db.getBook('$b/book/1'), isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(window(tester), same(original));
    await tester.tapAt(tester.getCenter(find.byType(ReaderPage))); // 收起仍在显示的菜单
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(780, 300));
    await tester.pumpAndSettle();
    expect(window(tester).offset, greaterThan(0));
    await leave(tester);
  });

  testWidgets('保存进度期间返回，保存完成不得在退场动画中重新打开换源页', (tester) async {
    await open(tester);
    await showMenu(tester);
    final entered = Completer<void>();
    final release = Completer<void>();
    final blocking = services.db.transaction(() async {
      entered.complete();
      await release.future;
    });
    await entered.future;
    try {
      await tester.tap(find.byTooltip('换书源'));
      await tester.pump();
      expect(openedSources, isEmpty, reason: '保存进度仍在等待事务锁');
      expect(find.byType(ChangeSourcePage), findsNothing);

      await tester.tap(find.byType(BackButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(ReaderPage, skipOffstage: false), findsOneWidget, reason: '阅读页仍在退场动画中，尚未 dispose');
      release.complete();
      await blocking;
      await tester.pump();
      expect(openedSources, isEmpty, reason: '即使阅读页仍 mounted，已经返回的 route 也不能再导航');
      await tester.pumpAndSettle();
      expect(find.text('打开阅读'), findsOneWidget);
      expect(find.byType(ReaderPage), findsNothing);
      expect(find.byType(ChangeSourcePage), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      if (!release.isCompleted) release.complete();
      await blocking;
    }
  });

  testWidgets('旧书源删除、正文加载失败时，菜单仍可直接换到可用书源', (tester) async {
    await services.repository.delete({SimpleBook.sourceUrl});
    await open(tester);
    expect(find.text('书源不存在'), findsOneWidget);
    await choose(tester, '书源乙');
    expect(window(tester).layoutOf(4)!.chapter.paragraphs.first.text, startsWith('书源乙'));
    expect(find.text('书源不存在'), findsNothing);
    await leave(tester);
  });

  testWidgets('未加入书架的试读书换源后仍未加入书架', (tester) async {
    await (services.db.update(
      services.db.books,
    )..where((book) => book.bookUrl.equals(SimpleBook.bookUrl))).write(const BooksCompanion(inShelf: Value(false), addedAt: Value(null)));
    await open(tester);
    await choose(tester, '书源乙');
    final changed = (await services.db.getBook('$b/book/1'))!;
    expect(changed.inShelf, isFalse);
    expect(changed.addedAt, isNull);
    expect(await services.db.shelf(), isEmpty);
    expect(window(tester).chapter, 4);
    await leave(tester);
  });

  testWidgets('旧书源的预取正文迟到，不重新写回已删除书籍的缓存，也不改变新阅读窗口', (tester) async {
    final pending = Completer<ChapterContent>();
    final content = services.engine.onContent!;
    services.engine.onContent = (source, book, chapter, next) =>
        source.bookSourceUrl == SimpleBook.sourceUrl && chapter.index == 4 ? pending.future : content(source, book, chapter, next);
    await open(tester);
    expect(services.engine.calls, contains('content /4.html'));
    await choose(tester, '书源乙');
    final current = window(tester);
    pending.complete(ChapterContent('旧书源迟到的正文', title: '第4章'));
    await tester.pumpAndSettle();
    expect(await services.db.getBook(SimpleBook.bookUrl), isNull);
    expect(await services.db.getContent(SimpleBook.bookUrl, '/4.html'), isNull);
    expect(window(tester), same(current));
    expect(current.layoutOf(4)!.chapter.paragraphs.first.text, startsWith('书源乙'));
    expect(tester.takeException(), isNull);
    await leave(tester);
  });

  testWidgets('换源后的阅读页仍保持屏幕常亮和阅读调暗效果', (tester) async {
    await open(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(ReaderPage)));
    final settings = container.read(readerSettingsProvider);
    container
        .read(readerSettingsProvider.notifier)
        .update(settings.copyWith(keepScreenOn: true, brightnessFollowSystem: false, brightness: 0.25));
    await tester.pumpAndSettle();
    expect(services.screen.calls.last, isTrue);
    expect(tester.widget<ColoredBox>(find.byKey(const ValueKey('reader-dimming'))).color, const Color(0x60000000));
    await choose(tester, '书源乙');
    expect(services.screen.calls.last, isTrue);
    expect(tester.widget<ColoredBox>(find.byKey(const ValueKey('reader-dimming'))).color, const Color(0x60000000));
    await leave(tester);
    expect(services.screen.calls.last, isFalse);
    expect(find.byKey(const ValueKey('reader-dimming')), findsNothing);
  });

  testWidgets('连续换源始终使用当前地址，返回一次即离开阅读页', (tester) async {
    await open(tester);
    await choose(tester, '书源乙');
    await choose(tester, '书源丙');
    expect(openedSources, [SimpleBook.bookUrl, '$b/book/1']);
    expect((await services.db.shelf()).single.book.bookUrl, '$c/book/1');
    expect(window(tester).layoutOf(4)!.chapter.paragraphs.first.text, startsWith('书源丙'));
    await leave(tester);
  });
}
