import 'package:flutter_test/flutter_test.dart';
import 'package:lanmao_reader/storage/write_queue.dart';

void main() {
  test('按顺序执行；一次失败交给 onError，后面的照常执行', () async {
    final errors = <Object>[];
    final done = <int>[];
    final queue = WriteQueue(onError: errors.add);
    queue.add(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      done.add(1);
    });
    queue.add(() async => throw StateError('写入失败'));
    queue.add(() async => done.add(3));
    await queue.flush();
    expect(done, [1, 3]);
    expect(errors.single, isA<StateError>());
  });
}
