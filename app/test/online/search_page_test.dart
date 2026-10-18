import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/online/search_page.dart';
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

  testWidgets('返回上一页后，未完成的搜索被取消', (tester) async {
    await services.addSources([{'bookSourceUrl': 'A', 'searchUrl': '/s'}]);
    services.engine.onSearch = (source, key) => Completer<List<SearchBook>>().future;
    await open(tester);
    await tester.enterText(find.byType(TextField), '三体');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(services.engine.batches.single.isStopped, isFalse);
    await tester.pageBack();
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
}
