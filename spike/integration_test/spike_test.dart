// flutter test integration_test -d <设备>
// AOT：flutter drive --profile --driver=test_driver/integration_test.dart --target=integration_test/spike_test.dart -d <设备>
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spike/spike_checks.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('纯 Flutter 路线前置验证', (tester) async {
    final results = await tester.runAsync(() => runSpikeChecks(onResult: print));
    final failed = results!.where((r) => !r.passed).toList();
    expect(failed, isEmpty, reason: failed.join('\n'));
  });

  testWidgets('worker 内存成本', (tester) async {
    debugPrint(await tester.runAsync(measureWorkerRss));
  });
}
