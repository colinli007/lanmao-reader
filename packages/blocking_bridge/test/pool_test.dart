import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:blocking_bridge/blocking_bridge.dart';
import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------- worker 里执行的任务
//
// 任务闭包要发送到 worker，它捕获的变量必须能跨 isolate 传递。Dart 闭包会捕获整个外层上下文，
// 所以都由顶层函数构造，避免把测试里的 WorkerPool（含 ReceivePort）一起捕获进去。

Object? Function() callHost(String op, [Object? payload]) => () => WorkerContext.current.callHost(op, payload);

/// 返回 [开始, 结束] 的时间戳（毫秒）。
List<int> Function() sleepFor(int ms) => () {
      final start = DateTime.now().millisecondsSinceEpoch;
      sleep(Duration(milliseconds: ms));
      return [start, DateTime.now().millisecondsSinceEpoch];
    };

/// 不检查中止信号的 Dart 计算。
int Function() spinFor(int ms) => () {
      final watch = Stopwatch()..start();
      while (watch.elapsedMilliseconds < ms) {}
      return ms;
    };

int Function() spinUntilCancelled() => () {
      final context = WorkerContext.current;
      var rounds = 0;
      while (!context.isCancelled) {
        rounds++;
      }
      return rounds;
    };

/// 每个 worker isolate 一个随机标记，用来判断两个任务是否跑在同一个 worker 上。
final int _workerMarker = Random().nextInt(1 << 32);
int Function() workerMarker() => () => _workerMarker;

/// 吞掉取消错误后再次请求宿主，把第二次请求的结果报告给 [report]。
void Function() swallowCancelThenCall(SendPort report) => () {
      final context = WorkerContext.current;
      try {
        context.callHost('slow');
      } on TaskCancelledException {
        try {
          context.callHost('again');
          report.send('no error');
        } on TaskCancelledException {
          report.send('cancelled');
        }
      }
    };

// ---------------------------------------------------------------- 栈上有 native 帧的任务
//
// 规则引擎的 Dart 代码常被 JS 回调调用，栈上夹着 C 帧。这里用 libc 的 qsort 回调 Dart 比较函数构造类似的栈，
// 验证 worker 在这种状态下被放弃、池被关闭时的流程。注意：立即 kill 导致的进程崩溃只在 QuickJS 宿主回调
// （返回指针、无 exceptionalReturn）上复现过，qsort 回调复现不了；那个崩溃的回归测试在 spike 的集成验证里。

typedef _Compare = Int Function(Pointer<Void>, Pointer<Void>);

final void Function(Pointer<Void>, int, int, Pointer<NativeFunction<_Compare>>) _qsort = DynamicLibrary.process()
    .lookupFunction<Void Function(Pointer<Void>, Size, Size, Pointer<NativeFunction<_Compare>>),
        void Function(Pointer<Void>, int, int, Pointer<NativeFunction<_Compare>>)>('qsort');

/// 在 qsort 的比较回调里执行 [body]（只执行一次），回调之外再检查一次取消。
void _insideNativeCallback(void Function() body) {
  var called = false;
  final compare = NativeCallable<_Compare>.isolateLocal((Pointer<Void> a, Pointer<Void> b) {
    if (!called) {
      called = true;
      body();
    }
    return 0;
  }, exceptionalReturn: 0);
  final items = calloc<Int32>(2);
  try {
    _qsort(items.cast(), 2, sizeOf<Int32>(), compare.nativeFunction);
  } finally {
    calloc.free(items);
    compare.close();
  }
  WorkerContext.current.throwIfCancelled();
}

/// 在 native 回调里阻塞等待宿主请求。
void Function() blockInsideNativeCallback() => () => _insideNativeCallback(() => WorkerContext.current.callHost('slow'));

/// 在 native 回调里做一段不检查中止信号的计算。
void Function() spinInsideNativeCallback(int ms) => () => _insideNativeCallback(() => spinFor(ms)());

Object? _stash;
int Function() stash({required bool create}) => () {
      if (create) _stash = Object();
      return identityHashCode(_stash);
    };

// ---------------------------------------------------------------- 主 isolate 上的宿主

class FakeHost {
  final List<HostCall> calls = [];
  Uint8List bytes = Uint8List(0);

  Iterable<String> get ops => calls.map((call) => call.op);

  Future<Object?> handle(HostCall call) async {
    calls.add(call);
    switch (call.op) {
      case 'delay':
        final [ms as int, value] = call.payload as List<Object?>;
        await Future<void>.delayed(Duration(milliseconds: ms));
        return value;
      case 'slow':
        await Future<void>.delayed(const Duration(seconds: 3));
        return 'slow';
      case 'interactive':
        call.markInteractive();
        await Future<void>.delayed(Duration(milliseconds: call.payload as int));
        return 'ok';
      case 'bytes':
        return bytes;
      case 'fail':
        throw StateError('网络不可用');
      default:
        return null;
    }
  }

  Future<HostCall> waitFor(String op, {int count = 1}) async {
    while (ops.where((o) => o == op).length < count) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return calls.lastWhere((call) => call.op == op);
  }
}

void main() {
  late FakeHost host;
  late WorkerPool pool;

  WorkerPool createPool({int size = 1, Duration? timeout, Duration grace = const Duration(seconds: 2)}) =>
      pool = WorkerPool(
        host.handle,
        size: size,
        defaultTimeout: timeout ?? const Duration(seconds: 30),
        cancelGracePeriod: grace,
      );

  setUp(() => host = FakeHost());
  tearDown(() => pool.close());

  group('在工作 isolate 中执行任务', () {
    test('返回值交回提交方', () async {
      createPool();
      expect(await pool.run(() => [1, 2, 3].map((x) => x * 2).join(',')), '2,4,6');
    });

    test('任务抛出异常，worker 之后可以继续执行', () async {
      createPool();
      await expectLater(pool.run(() => throw const FormatException('坏规则')), throwsA(isA<FormatException>()));
      expect(await pool.run(() => 'ok'), 'ok');
    });

    test('任务闭包不能跨 isolate 传递时提交方收到错误', () async {
      createPool();
      final port = ReceivePort();
      addTearDown(port.close);
      await expectLater(pool.run(() => port.hashCode), throwsA(isA<ArgumentError>()));
      expect(await pool.run(() => 'ok'), 'ok');
    });

    test('返回值不能跨 isolate 传递时提交方收到错误', () async {
      createPool();
      await expectLater(pool.run(ReceivePort.new), throwsA(isA<RemoteError>()));
    });
  });

  group('同步等待主 isolate 的宿主请求', () {
    test('同步拿到异步结果', () async {
      createPool();
      expect(await pool.run(callHost('delay', [300, '正文'])), '正文');
    });

    test('返回原始字节', () async {
      createPool();
      final random = Random(1);
      host.bytes = Uint8List.fromList(List.generate(1 << 20, (_) => random.nextInt(256)));
      final value = await pool.run(callHost('bytes'));
      expect(value, isA<Uint8List>());
      expect(value, host.bytes);
    });

    test('宿主处理失败，任务可以捕获并读到原因', () async {
      createPool();
      final value = await pool.run(() {
        try {
          WorkerContext.current.callHost('fail');
          return 'no error';
        } on HostCallException catch (e) {
          return 'caught: ${e.message}';
        }
      });
      expect(value, contains('网络不可用'));
    });

    test('等待期间主 isolate 照常运行', () async {
      createPool();
      var ticks = 0;
      final timer = Timer.periodic(const Duration(milliseconds: 50), (_) => ticks++);
      await pool.run(callHost('slow'));
      timer.cancel();
      expect(ticks, greaterThanOrEqualTo(40));
    });

    test('请求晚于取消到达：立即回复已取消，worker 不被替换', () async {
      createPool();
      final marker = await pool.run(workerMarker());
      final token = CancelToken();
      final pending = pool.run(callHost('slow'), cancelToken: token);
      // 阻塞主 isolate：worker 发出的请求留在端口里，取消先于请求被处理
      sleep(const Duration(milliseconds: 300));
      token.cancel();
      await expectLater(pending, throwsA(isA<TaskCancelledException>()));

      final watch = Stopwatch()..start();
      expect(await pool.run(workerMarker()), marker);
      expect(watch.elapsedMilliseconds, lessThan(1000));
      expect(host.ops, isNot(contains('slow')));
    });
  });

  group('并发上限与排队', () {
    test('并发不超过上限', () async {
      createPool(size: 2);
      final watch = Stopwatch()..start();
      final spans = await Future.wait([for (var i = 0; i < 5; i++) pool.run(sleepFor(1000))]);
      expect(watch.elapsedMilliseconds, inInclusiveRange(2900, 4500));
      for (final [start, _] in spans) {
        final overlapping = spans.where((span) => span[0] <= start && start < span[1]).length;
        expect(overlapping, lessThanOrEqualTo(2));
      }
      expect(pool.availableWorkers, 2);
    });

    test('多个任务并发阻塞', () async {
      createPool(size: 2);
      final watch = Stopwatch()..start();
      await Future.wait([pool.run(callHost('slow')), pool.run(callHost('slow'))]);
      expect(watch.elapsedMilliseconds, lessThan(5500));
    });

    test('先进先出', () async {
      createPool();
      final spans = await Future.wait([for (var i = 0; i < 3; i++) pool.run(sleepFor(50))]);
      final starts = [for (final [start, _] in spans) start];
      expect(starts, orderedEquals([...starts]..sort()));
    });
  });

  test('worker 内状态在任务间保留', () async {
    createPool();
    final created = await pool.run(stash(create: true));
    expect(await pool.run(stash(create: false)), created);
  });

  group('任务截止时间', () {
    test('宿主请求超过截止时间', () async {
      createPool();
      final watch = Stopwatch()..start();
      await expectLater(
        pool.run(callHost('slow'), timeout: const Duration(milliseconds: 500)),
        throwsA(isA<TaskTimeoutException>()),
      );
      expect(watch.elapsedMilliseconds, lessThan(2500));
      expect(await pool.run(() => 'ok'), 'ok');
    });

    test('计算超过截止时间：任务观察到中止信号', () async {
      // 宽限期很长：worker 很快空出来，只可能是任务自己观察到了中止信号
      createPool(grace: const Duration(seconds: 10));
      final marker = await pool.run(workerMarker());
      await expectLater(
        pool.run(spinUntilCancelled(), timeout: const Duration(milliseconds: 300)),
        throwsA(isA<TaskTimeoutException>()),
      );
      final watch = Stopwatch()..start();
      expect(await pool.run(workerMarker()), marker);
      expect(watch.elapsedMilliseconds, lessThan(1000));
    });

    test('等待用户时暂停计时', () async {
      createPool();
      final value = await pool.run(callHost('interactive', 3000), timeout: const Duration(seconds: 1));
      expect(value, 'ok');
    });
  });

  group('取消任务', () {
    test('一次取消一批任务，排队中的从未执行', () async {
      createPool(size: 2);
      final token = CancelToken();
      final futures = [
        for (var i = 0; i < 2; i++) pool.run(callHost('slow'), cancelToken: token),
        for (var i = 0; i < 3; i++) pool.run(callHost('mark'), cancelToken: token),
      ];
      await host.waitFor('slow', count: 2);
      token.cancel();
      for (final future in futures) {
        await expectLater(future, throwsA(isA<TaskCancelledException>()));
      }
      expect(host.ops, isNot(contains('mark')));
    });

    test('取消阻塞中的任务：立即返回，处理方收到通知，worker 很快空出', () async {
      createPool();
      final token = CancelToken();
      final pending = pool.run(callHost('slow'), cancelToken: token);
      final call = await host.waitFor('slow');
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final watch = Stopwatch()..start();
      token.cancel();
      await expectLater(pending, throwsA(isA<TaskCancelledException>()));
      expect(watch.elapsedMilliseconds, lessThan(100));
      await call.cancelled.timeout(const Duration(milliseconds: 100));

      expect(await pool.run(() => 'ok'), 'ok');
      expect(watch.elapsedMilliseconds, lessThan(1000));
    });

    test('取消正在执行的任务：任务观察到中止信号', () async {
      createPool(grace: const Duration(seconds: 10));
      final token = CancelToken();
      final pending = pool.run(spinUntilCancelled(), cancelToken: token);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      token.cancel();
      await expectLater(pending, throwsA(isA<TaskCancelledException>()));
      final watch = Stopwatch()..start();
      expect(await pool.run(() => 'ok'), 'ok');
      expect(watch.elapsedMilliseconds, lessThan(1000));
    });

    test('对已完成的任务取消没有影响', () async {
      createPool(size: 2);
      final token = CancelToken();
      final done = pool.run(() => 'done', cancelToken: token);
      expect(await done, 'done');
      final pending = pool.run(callHost('slow'), cancelToken: token);
      await host.waitFor('slow');
      token
        ..cancel()
        ..cancel();
      await expectLater(pending, throwsA(isA<TaskCancelledException>()));
      expect(await done, 'done');
      expect(await pool.run(() => 'ok'), 'ok');
    });

    test('已取消的令牌提交任务立即失败', () async {
      createPool();
      final token = CancelToken()..cancel();
      await expectLater(pool.run(() => 'x', cancelToken: token), throwsA(isA<TaskCancelledException>()));
    });
  });

  test('被取消的任务不再发起宿主请求', () async {
    createPool();
    final report = ReceivePort();
    addTearDown(report.close);
    final sendPort = report.sendPort;
    final token = CancelToken();
    final pending = pool.run(swallowCancelThenCall(sendPort), cancelToken: token);
    await host.waitFor('slow');
    token.cancel();
    await expectLater(pending, throwsA(isA<TaskCancelledException>()));
    expect(await report.first, 'cancelled');
    expect(host.ops, isNot(contains('again')));
  });

  group('停不下来的 worker 被替换', () {
    test('计算不响应取消：补位后新任务很快在新 worker 上执行', () async {
      createPool(grace: const Duration(milliseconds: 300));
      final marker = await pool.run(workerMarker());
      final token = CancelToken();
      final pending = pool.run(spinFor(10000), cancelToken: token);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      token.cancel();
      await expectLater(pending, throwsA(isA<TaskCancelledException>()));

      final watch = Stopwatch()..start();
      final next = await pool.run(workerMarker());
      expect(next, isNot(marker));
      expect(watch.elapsedMilliseconds, lessThan(2000));
    });

    test('替换后可用 worker 数不超过上限', () async {
      createPool(size: 2, grace: const Duration(milliseconds: 200));
      var peak = 0;
      final sampler = Timer.periodic(const Duration(milliseconds: 2), (_) => peak = max(peak, pool.availableWorkers));
      addTearDown(sampler.cancel);

      final token = CancelToken();
      final pending = [for (var i = 0; i < 2; i++) pool.run(spinFor(10000), cancelToken: token)];
      await Future<void>.delayed(const Duration(milliseconds: 100));
      token.cancel();
      for (final future in pending) {
        await expectLater(future, throwsA(isA<TaskCancelledException>()));
      }
      final watch = Stopwatch()..start();
      await Future.wait([pool.run(() => 1), pool.run(() => 2), pool.run(() => 3)]);
      expect(watch.elapsedMilliseconds, lessThan(2000));
      expect(peak, lessThanOrEqualTo(2));
    });
  });

  group('任务在 native 回调中', () {
    test('阻塞在 native 回调里时关闭池', () async {
      createPool();
      final pending = pool.run(blockInsideNativeCallback());
      await host.waitFor('slow');
      pool.close();
      await expectLater(pending, throwsA(isA<StateError>()));
      // 进程还活着：再开一个池正常干活
      expect(await createPool().run(() => 'alive'), 'alive');
    });

    test('在 native 回调里不响应取消，被放弃后计算结束时退出', () async {
      createPool(grace: const Duration(milliseconds: 200));
      final token = CancelToken();
      final pending = pool.run(spinInsideNativeCallback(1500), cancelToken: token);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      token.cancel();
      await expectLater(pending, throwsA(isA<TaskCancelledException>()));
      expect(await pool.run(() => 'replacement'), 'replacement');
      // 等被放弃的 worker 的计算结束、自行退出
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(await pool.run(() => 'alive'), 'alive');
    });
  });

  test('worker 在任务中退出：任务以错误结束，排队的任务在新 worker 上完成', () async {
    createPool();
    final crashed = pool.run(() => Isolate.exit());
    final next = pool.run(() => 'next');
    await expectLater(crashed, throwsA(isA<WorkerExitedException>()));
    expect(await next, 'next');
  });

  group('关闭池', () {
    test('关闭时有阻塞中的任务：很快完成，提交方收到错误，处理方收到通知', () async {
      createPool();
      final pending = pool.run(callHost('slow'));
      final call = await host.waitFor('slow');
      final watch = Stopwatch()..start();
      pool.close();
      expect(watch.elapsedMilliseconds, lessThan(100));
      await expectLater(pending, throwsA(isA<StateError>()));
      await call.cancelled.timeout(const Duration(milliseconds: 100));
    });

    test('关闭后提交立即失败', () async {
      createPool().close();
      await expectLater(pool.run(() => 1), throwsA(isA<StateError>()));
    });
  });
}
