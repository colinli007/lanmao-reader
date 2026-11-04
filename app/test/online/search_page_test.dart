import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanmao_reader/online/search_page.dart';
import 'package:rule_engine/rule_engine.dart';

import '../support/test_app.dart';

void main() {
  late TestServices services;
  setUp(() async => services = await TestServices.create());
  tearDown(() => services.db.close());

  SearchBook result(String source, String name) => SearchBook(bookUrl: '$source/$name', origin: source, originName: source)
    ..name = name
    ..author = '刘慈欣';

  /// 搜索页压在一个空页面上，这样能返回。
  Widget app() => services.app(
    Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SearchPage())),
          child: const Text('去搜索'),
        ),
      ),
    ),
  );

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('去搜索'));
    await tester.pumpAndSettle();
  }

  testWidgets('结果逐步出现，显示进度，全部完成后显示结束', (tester) async {
    await services.addSources([
      {'bookSourceUrl': 'A', 'searchUrl': '/s', 'bookSourceName': '甲'},
      {'bookSourceUrl': 'B', 'searchUrl': '/s', 'bookSourceName': '乙'},
    ]);
    final pending = <String, Completer<List<SearchBook>>>{};
    services.engine.onSearch = (source, key) => (pending[source.bookSourceUrl] = Completer()).future;
    await open(tester);
    await tester.enterText(find.byType(TextField), '三体');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(find.text('已完成 0/2 个书源'), findsOneWidget);

    pending['A']!.complete([result('A', '三体')]);
    await tester.pump();
    expect(find.text('已完成 1/2 个书源'), findsOneWidget);
    expect(find.text('三体'), findsWidgets);
    expect(find.text('1 个书源'), findsOneWidget);

    pending['B']!.completeError(UnsupportedHostApiException('java.startBrowserAwait', sourceName: '乙'));
    await tester.pump();
    expect(find.text('搜索结束，共 1 本'), findsOneWidget);
    await tester.tap(find.text('失败 1 个'));
    await tester.pumpAndSettle();
    expect(find.text('不支持的宿主 API：java.startBrowserAwait（乙）'), findsOneWidget);
  });

  testWidgets('没有可用书源时显示提示，不发请求', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), '三体');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(find.text('没有可以搜索的书源，先去导入或启用书源'), findsOneWidget);
    expect(services.engine.calls, isEmpty);
  });

  testWidgets('点「取消」返回上一页后，未完成的搜索被取消', (tester) async {
    await services.addSources([{'bookSourceUrl': 'A', 'searchUrl': '/s'}]);
    services.engine.onSearch = (source, key) => Completer<List<SearchBook>>().future;
    await open(tester);
    await tester.enterText(find.byType(TextField), '三体');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(services.engine.batches.single.isStopped, isFalse);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(services.engine.batches.single.isStopped, isTrue);
  });

  testWidgets('点停止后保留结果，不再显示进度条', (tester) async {
    await services.addSources([{'bookSourceUrl': 'A', 'searchUrl': '/s'}, {'bookSourceUrl': 'B', 'searchUrl': '/s'}]);
    final pending = <String, Completer<List<SearchBook>>>{};
    services.engine.onSearch = (source, key) => (pending[source.bookSourceUrl] = Completer()).future;
    await open(tester);
    await tester.enterText(find.byType(TextField), '三体');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    pending['A']!.complete([result('A', '三体')]);
    await tester.pump();
    await tester.tap(find.text('停止'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('搜索结束，共 1 本'), findsOneWidget);
  });
  group('搜索历史', () {
    Future<void> submit(WidgetTester tester, String key) async {
      await tester.enterText(find.byType(TextField), key);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
    }

    /// 搜索历史里的词，按显示的先后。
    List<String> history(WidgetTester tester) => [
      for (final element in find.descendant(of: find.byType(Wrap), matching: find.byType(Text)).evaluate())
        (element.widget as Text).data!,
    ];

    /// 搜索历史里每个词的使用次数。
    Future<Map<String, int>> usage() async => {
      for (final row in await services.db.select(services.db.searchKeywords).get()) row.word: row.usage,
    };

    testWidgets('没有历史时不显示；提交时记下（去掉首尾空白）', (tester) async {
      await open(tester);
      expect(find.text('搜索历史'), findsNothing);
      await submit(tester, ' 三体 ');
      await submit(tester, '三体');
      expect(await usage(), {'三体': 2});
    });

    testWidgets('空输入框按最近使用排，有字时按次数过滤；空白不提交', (tester) async {
      // 存的时间精确到秒，测试里连着搜几次会同一秒，所以先写入有先后的历史
      for (final (word, day) in [('三体前传', 1), ('斗罗', 2), ('三体前传', 3), ('三体前传', 4)]) {
        await services.db.useSearchKeyword(word, DateTime(2026, 1, day));
      }
      await open(tester);
      expect(history(tester), ['三体前传', '斗罗']);
      await submit(tester, '三体');
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(history(tester), ['三体', '三体前传', '斗罗']);
      await tester.enterText(find.byType(TextField), '三体');
      await tester.pumpAndSettle();
      expect(history(tester), ['三体前传', '三体']);
      await tester.enterText(find.byType(TextField), '   ');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('搜索历史'), findsOneWidget, reason: '空白不提交，仍显示历史');
    });

    testWidgets('点历史词：填进输入框并搜索，次数加一', (tester) async {
      await services.addSources([{'bookSourceUrl': 'A', 'searchUrl': '/s', 'bookSourceName': '甲'}]);
      final keys = <String>[];
      services.engine.onSearch = (source, key) async {
        keys.add(key);
        return [result('A', key)];
      };
      await open(tester);
      await submit(tester, '三体');
      await submit(tester, '斗罗');
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      await tester.tap(find.text('三体'));
      await tester.pumpAndSettle();
      expect(keys, ['三体', '斗罗', '三体']);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '三体');
      expect(find.text('搜索历史'), findsNothing);
      expect(find.text('搜索结束，共 1 本'), findsOneWidget);
      expect(await usage(), {'三体': 2, '斗罗': 1});
    });

    testWidgets('改输入框时停止搜索，显示历史', (tester) async {
      await services.addSources([{'bookSourceUrl': 'A', 'searchUrl': '/s'}]);
      services.engine.onSearch = (source, key) => Completer<List<SearchBook>>().future;
      await open(tester);
      await tester.enterText(find.byType(TextField), '三体');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(services.engine.batches.single.isStopped, isFalse);
      await tester.enterText(find.byType(TextField), '三');
      await tester.pumpAndSettle();
      expect(services.engine.batches.single.isStopped, isTrue);
      expect(history(tester), ['三体']);
      expect(find.textContaining('已完成'), findsNothing);
    });

    testWidgets('长按删一条；清除确认后删全部，不再显示', (tester) async {
      await open(tester);
      await submit(tester, '三体');
      await submit(tester, '斗罗');
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      await tester.longPress(find.text('斗罗'));
      await tester.pumpAndSettle();
      expect(history(tester), ['三体']);
      await tester.tap(find.text('清除'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '清除'));
      await tester.pumpAndSettle();
      expect(find.text('搜索历史'), findsNothing);
      expect(await usage(), isEmpty);
    });
  });
}
