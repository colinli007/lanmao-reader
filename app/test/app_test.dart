import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/app.dart';

import 'support/test_app.dart';

void main() {
  testWidgets('书架顶栏进入搜索，设置 tab 进入书源', (tester) async {
    final services = await TestServices.create();
    await tester.pumpWidget(ProviderScope(overrides: services.overrides, child: const NovelReaderApp()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('书源'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '书源'), findsOneWidget);
    await services.db.close();
  });
}
