import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/app.dart';
import 'package:novel_reader/bookshelf/bookshelf_page.dart';
import 'package:novel_reader/storage/database.dart';

import 'support/test_app.dart';

void main() {
  testWidgets('书架顶栏进入搜索；底部 Tab 切到书源和我的，发现还没做只提示', (tester) async {
    final services = await TestServices.create();
    await tester.pumpWidget(ProviderScope(overrides: services.overrides, child: const NovelReaderApp()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('书源'));
    await tester.pumpAndSettle();
    expect(find.text('搜索书源名称或网址'), findsOneWidget);
    await tester.tap(find.byTooltip('我的'));
    await tester.pumpAndSettle();
    expect(find.text('替换净化规则'), findsOneWidget);
    await tester.tap(find.byTooltip('发现'));
    await tester.pump();
    expect(find.text('发现暂未开发'), findsOneWidget);
    expect(find.text('替换净化规则'), findsOneWidget);
    await tester.pumpAndSettle();
    await services.db.close();
  });

  testWidgets('外壳是深色的，不跟随系统', (tester) async {
    final services = await TestServices.create();
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(ProviderScope(overrides: services.overrides, child: const NovelReaderApp()));
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.byType(BookshelfPage))).brightness, Brightness.dark);
    await services.db.close();
  });

  testWidgets('每次切到「我的」重新统计正文缓存', (tester) async {
    final services = await TestServices.create();
    await tester.pumpWidget(ProviderScope(overrides: services.overrides, child: const NovelReaderApp()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('我的'));
    await tester.pumpAndSettle();
    expect(find.text('0 章 · 0 B'), findsOneWidget);
    await tester.tap(find.byTooltip('书架'));
    await tester.pumpAndSettle();
    await services.db.putContent(const ContentRow(bookUrl: 'b', chapterUrl: 'c', title: '', content: '正文'));
    await tester.tap(find.byTooltip('我的'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 章 · '), findsOneWidget);
    await services.db.close();
  });
}
