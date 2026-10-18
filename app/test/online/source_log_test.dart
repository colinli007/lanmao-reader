import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/online/source_log.dart';
import 'package:novel_reader/online/source_log_page.dart';
import 'package:rule_engine/rule_engine.dart';

import '../support/test_app.dart';

void main() {
  test('只保留 500 条，新的在前', () {
    final log = SourceLogBuffer();
    for (var i = 0; i < 501; i++) {
      log.addSourceLog(SourceLog(sourceUrl: 'https://a.com', message: '$i'));
    }
    expect(log.entries, hasLength(500));
    expect((log.entries.first.message, log.entries.last.message), ('500', '1'));
  });

  testWidgets('RuleHost 交出的日志显示在最上面，书源名取当前的名字，删除后显示地址', (tester) async {
    final services = await TestServices.create();
    await services.addSources([{'bookSourceUrl': 'https://a.com', 'bookSourceName': 'A'}]);
    // 和 startup 一样：RuleHost.onLog 接到缓冲区
    final host = RuleHost(onLog: services.log.addSourceLog);
    host.onLog!(const SourceLog(sourceUrl: 'https://a.com', field: 'ruleSearch.name', message: 'old'));
    host.onLog!(const SourceLog(sourceUrl: 'https://a.com', field: 'ruleSearch.name', message: 'hi'));
    services.log.addStorageError(StateError('磁盘满'));
    await tester.pumpWidget(services.app(const SourceLogPage()));
    final titles = tester.widgetList<SelectableText>(find.byType(SelectableText)).map((t) => t.data).toList();
    expect(titles, ['落盘失败：Bad state: 磁盘满', 'hi', 'old']);
    expect(find.textContaining('A · ruleSearch.name'), findsNWidgets(2));
    expect(find.textContaining('存储'), findsOneWidget);

    await services.repository.delete({'https://a.com'});
    await tester.pump();
    expect(find.textContaining('https://a.com · ruleSearch.name'), findsNWidgets(2));

    await tester.tap(find.byTooltip('清空'));
    await tester.pump();
    expect(find.text('没有日志'), findsOneWidget);
    await services.db.close();
  });
}
