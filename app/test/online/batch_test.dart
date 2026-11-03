import 'dart:async';

import 'package:blocking_bridge/blocking_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanmao_reader/online/batch.dart';

void main() {
  test('提交 20 个任务，同时最多 6 个', () async {
    final limiter = BatchLimiter(6);
    final batch = Batch();
    var running = 0;
    var peak = 0;
    final results = await Future.wait([
      for (var i = 0; i < 20; i++)
        limiter.run(batch, (_) async {
          peak = (++running) > peak ? running : peak;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          running--;
          return i;
        }),
    ]);
    expect(results, List.generate(20, (i) => i));
    expect(peak, 6);
  });

  test('停止后排队的任务以取消结束、不再提交，别的批次照常', () async {
    final limiter = BatchLimiter(1);
    final stopped = Batch();
    final other = Batch();
    final gate = Completer<void>();
    final submitted = <String>[];
    Future<void> task(Batch batch, String name, [Future<void>? until]) =>
        limiter.run(batch, (token) async {
          submitted.add(name);
          await until;
        });

    final first = task(stopped, 'first', gate.future);
    final queued = task(stopped, 'queued');
    final otherTask = task(other, 'other');
    stopped.stop();
    await expectLater(queued, throwsA(isA<TaskCancelledException>()));
    expect(stopped.token.isCancelled, isTrue);
    gate.complete();
    await first;
    await otherTask;
    expect(submitted, ['first', 'other']);
    await expectLater(task(stopped, 'late'), throwsA(isA<TaskCancelledException>()));
  });
  test('stop 之后 stopped 完成，重复 stop 不报错', () async {
    final batch = Batch();
    var stopped = false;
    unawaited(batch.stopped.then((_) => stopped = true));
    await Future<void>.delayed(Duration.zero);
    expect(stopped, isFalse);
    batch.stop();
    batch.stop();
    await batch.stopped;
    expect(stopped, isTrue);
  });
}
