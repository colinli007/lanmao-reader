import 'package:blocking_bridge/blocking_bridge.dart';
import 'package:rule_engine/src/rule/analyze_rule.dart';
import 'package:rule_engine/src/worker/worker_environment.dart';
import 'package:test/test.dart';

// 「书源正则可以被中止」：在 worker 池里执行灾难性回溯的净化规则，取消后 worker 不被放弃
void main() {
  late WorkerPool pool;

  setUp(() {
    pool = WorkerPool((call) async => null, size: 1, cancelGracePeriod: const Duration(seconds: 2));
  });
  tearDown(() => pool.close());

  test('灾难性回溯被取消，worker 没有被放弃', () async {
    // 先跑一个任务，确保 worker 和它的正则引擎已经就绪，计时只算匹配
    expect(await pool.run(_purify('ab', r'text##(a+)+b##x')), 'x');

    final token = CancelToken();
    final future = pool.run(_purify('a' * 30, r'text##(a+)+b##x'), cancelToken: token);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final watch = Stopwatch()..start();
    token.cancel();
    await expectLater(future, throwsA(isA<TaskCancelledException>()));

    // worker 在宽限期内结束了任务：没有被放弃，下一个任务立即在同一个 worker 上执行
    expect(await pool.run(_purify('aab', r'text##(a+)+b##x')), 'x');
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    expect(pool.availableWorkers, 1);
  });
}

String Function() _purify(String content, String rule) =>
    () => (AnalyzeRule(const WorkerRuleEnvironment())..setContent(content)).getString(rule);
