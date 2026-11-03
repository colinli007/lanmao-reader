import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanmao_reader/reader/toc_page.dart';
import 'package:lanmao_reader/storage/database.dart';
import 'package:lanmao_reader/ui/icons.dart';

import '../support/test_app.dart';

const _bookUrl = 'https://a.com/book/1';

TocChapter _chapter(int index, String title, {bool volume = false}) => TocChapter(
  bookUrl: _bookUrl,
  idx: index,
  url: '/$index',
  title: title,
  isVolume: volume,
  isVip: false,
  isPay: false,
  sourceData: '{}',
);

void main() {
  late TestServices services;
  setUp(() async => services = await TestServices.create());
  tearDown(() => services.db.close());

  /// 打开目录页，返回点章节后带回来的下标。
  Future<Future<int?>> open(WidgetTester tester, List<TocChapter> chapters, {int? current}) async {
    late Future<int?> result;
    await tester.pumpWidget(
      services.app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => result = Navigator.of(context).push<int>(
              MaterialPageRoute(builder: (_) => TocPage(bookUrl: _bookUrl, bookName: '三体', chapters: chapters, current: current)),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    return result;
  }

  /// 列表里从上到下的文字。
  List<String> rows(WidgetTester tester) => [
    for (final element in find.descendant(of: find.byType(ListView), matching: find.byType(Text)).evaluate())
      (element.widget as Text).data!,
  ];

  final volumes = [
    _chapter(0, '卷一', volume: true),
    _chapter(1, '第1章'),
    _chapter(2, '第2章'),
    _chapter(3, '卷二', volume: true),
    _chapter(4, '第3章'),
    _chapter(5, '第4章'),
  ];

  testWidgets('卷显示为分组标题，不能点击；点章节带着下标返回', (tester) async {
    final result = await open(tester, volumes);
    expect(find.text('共 4 章 · 已缓存 0 章'), findsOneWidget);
    await tester.tap(find.text('卷一'));
    await tester.pumpAndSettle();
    expect(find.byType(TocPage), findsOneWidget);
    await tester.tap(find.text('第3章'));
    await tester.pumpAndSettle();
    expect(await result, 4);
  });

  testWidgets('已缓存标记：标出已缓存的章节，顶部显示已缓存章数', (tester) async {
    for (final url in ['/1', '/2']) {
      await services.db.putContent(ContentRow(bookUrl: _bookUrl, chapterUrl: url, title: 't', content: 'c'));
    }
    await open(tester, volumes);
    expect(find.text('共 4 章 · 已缓存 2 章'), findsOneWidget);
    expect(find.byIcon(LucideIcons.checkCircle2), findsNWidgets(2));
    expect(find.descendant(of: find.ancestor(of: find.text('第1章'), matching: find.byType(Row)), matching: find.byIcon(LucideIcons.checkCircle2)), findsOneWidget);
    expect(find.descendant(of: find.ancestor(of: find.text('第3章'), matching: find.byType(Row)), matching: find.byIcon(LucideIcons.checkCircle2)), findsNothing);
  });

  testWidgets('倒序：章节从后往前，卷标题仍在卷的章节前面；再点回到正序', (tester) async {
    await open(tester, volumes);
    expect(rows(tester), ['卷一', '第1章', '第2章', '卷二', '第3章', '第4章']);
    await tester.tap(find.byTooltip('倒序'));
    await tester.pumpAndSettle();
    expect(rows(tester), ['卷二', '第4章', '第3章', '卷一', '第2章', '第1章']);
    await tester.tap(find.byTooltip('正序'));
    await tester.pumpAndSettle();
    expect(rows(tester), ['卷一', '第1章', '第2章', '卷二', '第3章', '第4章']);
  });

  testWidgets('打开时当前章在可见区域内；滚走后「回到当前」把它滚回来', (tester) async {
    final chapters = [for (var i = 0; i < 1000; i++) _chapter(i, '第${i + 1}章')];
    await open(tester, chapters, current: 499);
    expect(find.text('第500章').hitTestable(), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, 5000));
    await tester.pumpAndSettle();
    expect(find.text('第500章'), findsNothing);
    await tester.tap(find.byTooltip('回到当前'));
    await tester.pumpAndSettle();
    expect(find.text('第500章').hitTestable(), findsOneWidget);
  });

  testWidgets('没有当前章时没有「回到当前」', (tester) async {
    await open(tester, volumes);
    expect(find.byTooltip('回到当前'), findsNothing);
  });
}
