// 替换净化的耗时（add-replace-rules 任务 6.2，profile 构建）：
//   flutter drive --profile --driver=test_driver/integration_test.dart --target=integration_test/replace_rules_perf_test.dart \
//     -d emulator-5554
// 100 条都不匹配的正则规则，对一章约 10 KB 的正文执行 purify：真的 worker 池和 quickjs，每条正则一次 isolate 往返（设计 D2）。
// 先预热一次（worker 启动、正则编译），再测 10 次，结果以 REPORT 开头打印。
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lanmao_reader/library/providers.dart';
import 'package:lanmao_reader/online/providers.dart';
import 'package:lanmao_reader/online/startup.dart';
import 'package:lanmao_reader/storage/database.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('100 条正则规则处理一章 10 KB 正文', (tester) async {
    final container = ProviderContainer(overrides: await startServices(database: AppDatabase(NativeDatabase.memory())));
    addTearDown(container.dispose);
    final rules = container.read(replaceRuleRepositoryProvider);
    final engine = container.read(sourceEngineProvider);
    await rules.import(
      (await engine.loadReplaceRules('[${[for (var i = 0; i < 100; i++) '{"id": $i, "pattern": "广告$i[A-Z]+\\\\d{2,}"}'].join(',')}]')).rules,
    );
    expect(rules.entries, hasLength(100));

    const book = ShelfBook(
      bookUrl: 'local://perf',
      origin: 'local://perf',
      originName: '本地',
      name: '性能',
      author: '测试',
      durChapterIndex: 0,
      durChapterPos: 0,
      inShelf: true,
      sourceData: '{}',
    );
    // 每段 45 字，70 段，约 3200 字、UTF-8 约 10 KB
    final content = List.filled(70, '山风从谷底卷上来，吹得崖边的松枝簌簌作响。他站在最高的那块石头上，望着远处渐渐亮起的天色。').join('\n');
    final source = container.read(contentSourceProvider);
    Future<int> run() async {
      final watch = Stopwatch()..start();
      final purified = await source.purify(book, (title: '第1章', content: content));
      expect(purified.text.content, content);
      return watch.elapsedMilliseconds;
    }

    await run();
    final times = [for (var i = 0; i < 10; i++) await run()]..sort();
    final median = (times[4] + times[5]) / 2;
    debugPrint('REPORT 100 条正则规则、${content.length} 字：中位数 ${median}ms，各次 $times');
    expect(median, lessThanOrEqualTo(100));
  });
}
