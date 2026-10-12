/// 纯 Flutter 路线的前置验证项。集成测试和演示界面共用这一份。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:blocking_bridge/blocking_bridge.dart';

import 'js_tasks.dart';
import 'rule_engine_check.dart';

class CheckResult {
  CheckResult(this.name, this.passed, this.detail, this.elapsed);

  final String name;
  final bool passed;
  final String detail;
  final Duration elapsed;

  @override
  String toString() => '${passed ? 'PASS' : 'FAIL'}  $name  (${elapsed.inMilliseconds}ms)  $detail';
}

typedef _Check = Future<String> Function(_Fixture fixture);

/// 本地 HTTP 服务：`/hello` 立即返回，`/slow` 3 秒后返回。
class _Fixture {
  _Fixture._(this.server);

  final HttpServer server;
  final List<WorkerPool> pools = [];

  String get base => 'http://127.0.0.1:${server.port}';

  static Future<_Fixture> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.uri.path == '/slow') {
        await Future<void>.delayed(const Duration(seconds: 3));
      }
      request.response
        ..headers.contentType = ContentType('text', 'plain', charset: 'utf-8')
        ..write('你好 ${request.uri.path}');
      await request.response.close();
    });
    return _Fixture._(server);
  }

  WorkerPool pool({int size = 1, Duration grace = const Duration(seconds: 2)}) {
    final pool = WorkerPool(
      _handleHostRequest,
      size: size,
      defaultTimeout: const Duration(seconds: 15),
      cancelGracePeriod: grace,
    );
    pools.add(pool);
    return pool;
  }

  Future<void> close() async {
    for (final pool in pools) {
      pool.close();
    }
    await server.close(force: true);
  }
}

/// 主 isolate 上的宿主实现：全部是普通的异步代码。
Future<Object?> _handleHostRequest(HostCall call) async {
  final args = call.payload as List<Object?>;
  switch (HostOp.values.byName(call.op)) {
    case HostOp.httpGet:
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      // 任务结束（取消、超时、池关闭）时中断请求
      unawaited(call.cancelled.then((_) => client.close(force: true)));
      try {
        final request = await client.getUrl(Uri.parse(args[0] as String));
        final response = await request.close();
        return await response.transform(const Utf8Decoder(allowMalformed: true)).join();
      } finally {
        client.close(force: true);
      }
    case HostOp.verificationCode:
      // 模拟弹出验证码输入框、等用户输入：等待期间不计入任务截止时间
      call.markInteractive();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return 'code-for-${args[0]}';
  }
}

/// 等 [future] 以 [T] 类型的错误结束，返回用时。
Future<int> _expectError<T extends Object>(Future<Object?> future) async {
  final watch = Stopwatch()..start();
  try {
    final value = await future;
    throw StateError('期望 $T，却返回了 $value');
  } on T {
    return watch.elapsedMilliseconds;
  }
}

final Map<String, _Check> _checks = {
  '工作 isolate 里求值': (f) async {
    final value = await f.pool().run(evalJs('[1, 2, 3].map(x => x * 2).join(",")'));
    _expect(value == '2,4,6', 'got $value');
    return '$value';
  },
  'JS 同步 ajax（本地 HTTP）': (f) async {
    final value = await f.pool().run(evalJs(
      'var html = java.ajax(base + "/hello"); html.length + ":" + html',
      globals: {'base': f.base},
    ));
    _expect('$value'.endsWith('你好 /hello'), 'got $value');
    return '$value';
  },
  'JS 同步 ajax（HTTPS 外网）': (f) async {
    final value = await f.pool().run(evalJs('java.ajax("https://example.com").indexOf("Example Domain") >= 0'));
    _expect(value == true, 'got $value');
    return 'example.com 正文包含 Example Domain';
  },
  '同步等待「用户输入」（验证码 / WebView 同一机制），等待期间不计入截止时间': (f) async {
    final watch = Stopwatch()..start();
    final value = await f.pool().run(
      evalJs('java.getVerificationCode("https://a.com/captcha.png")'),
      timeout: const Duration(milliseconds: 100),
    );
    _expect(value == 'code-for-https://a.com/captcha.png', 'got $value');
    _expect(watch.elapsedMilliseconds >= 300, '等待时间不足 ${watch.elapsedMilliseconds}ms');
    return '$value';
  },
  '嵌套：规则回调里的 JS 再同步 ajax': (f) async {
    final value = await f.pool().run(evalJs(
      'java.getString("@js:java.ajax(base + \'/hello\').toUpperCase()")',
      globals: {'base': f.base},
    ));
    _expect('$value'.contains('/HELLO'), 'got $value');
    return '$value';
  },
  '阻塞中的宿主请求超过截止时间': (f) async {
    final pool = f.pool();
    final ms = await _expectError<TaskTimeoutException>(pool.run(
      evalJs('java.ajax(base + "/slow")', globals: {'base': f.base}),
      timeout: const Duration(milliseconds: 500),
    ));
    _expect(ms < 2500, '没有按截止时间返回：${ms}ms');
    final value = await pool.run(evalJs('"still alive"'));
    _expect(value == 'still alive', 'got $value');
    return '${ms}ms 收到超时，worker 仍可用';
  },
  '工作 isolate 阻塞时主 isolate 不卡': (f) async {
    var ticks = 0;
    final timer = Timer.periodic(const Duration(milliseconds: 50), (_) => ticks++);
    await f.pool().run(evalJs('java.ajax(base + "/slow")', globals: {'base': f.base}));
    timer.cancel();
    // 3 秒内理论上有 60 次，留足余量
    _expect(ticks >= 40, '主 isolate 定时器只触发了 $ticks 次');
    return '阻塞 3 秒期间主 isolate 定时器触发 $ticks 次';
  },
  '两个 worker 并发阻塞': (f) async {
    final pool = f.pool(size: 2);
    final watch = Stopwatch()..start();
    final results = await Future.wait([
      for (var i = 0; i < 2; i++) pool.run(evalJs('java.ajax(base + "/slow")', globals: {'base': f.base})),
    ]);
    final ms = watch.elapsedMilliseconds;
    _expect(results.every((r) => '$r'.contains('/slow')), 'got $results');
    _expect(ms < 5500, '串行了：${ms}ms');
    return '两个 3 秒请求共耗时 ${ms}ms';
  },
  '关闭池时阻塞中的 worker 不会卡住': (f) async {
    final pool = f.pool();
    final pending = pool.run(evalJs('java.ajax(base + "/slow")', globals: {'base': f.base}));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final watch = Stopwatch()..start();
    pool.close();
    final closeMs = watch.elapsedMilliseconds;
    await _expectError<StateError>(pending);
    return 'close 返回用时 ${closeMs}ms';
  },
  '压力：4 个 worker 各 300 轮注入变量 + 求值 + 阻塞调用': (f) async {
    final pool = f.pool(size: 4);
    final watch = Stopwatch()..start();
    await Future.wait([
      for (var lane = 0; lane < 4; lane++)
        () async {
          for (var round = 0; round < 300; round++) {
            final value = await pool.run(evalJs(
              'java.ajax(base + "/hello").length + n',
              globals: {'base': f.base, 'n': round},
            ));
            _expect(value == 9 + round, 'lane $lane round $round got $value');
          }
        }(),
    ]);
    _expect(pool.availableWorkers == 4, 'worker 数 ${pool.availableWorkers}');
    return '1200 次共 ${watch.elapsedMilliseconds}ms';
  },
  'JS 死循环超过截止时间被中止': (f) async {
    final pool = f.pool();
    await _expectError<TaskTimeoutException>(
      pool.run(evalJs('while (true) {}'), timeout: const Duration(milliseconds: 300)),
    );
    final value = await pool.run(evalJs('"still alive"'));
    _expect(value == 'still alive', 'got $value');
    return '中止后引擎仍可用';
  },
  '取消：JS 死循环': (f) async {
    final pool = f.pool();
    final token = CancelToken();
    final pending = pool.run(evalJs('while (true) {}'), cancelToken: token);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    token.cancel();
    await _expectError<TaskCancelledException>(pending);
    final watch = Stopwatch()..start();
    final value = await pool.run(evalJs('"still alive"'));
    _expect(value == 'still alive' && watch.elapsedMilliseconds < 1000, 'got $value');
    return 'worker ${watch.elapsedMilliseconds}ms 后可用';
  },
  '取消：阻塞中的 java.ajax，外层 try/catch 拦不住': (f) async {
    final pool = f.pool();
    final token = CancelToken();
    final pending = pool.run(
      evalJs('try { java.ajax(base + "/slow") } catch (e) {} java.log("continued")', globals: {'base': f.base}),
      cancelToken: token,
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    token.cancel();
    final ms = await _expectError<TaskCancelledException>(pending);
    _expect(ms < 100, '取消用时 ${ms}ms');
    final logs = await pool.run(takeLogs());
    _expect(logs.isEmpty, 'JS 在 catch 之后继续执行了：$logs');
    return '${ms}ms 收到取消，JS 没有继续执行';
  },
  '取消：一次取消一批任务': (f) async {
    final pool = f.pool(size: 2);
    final token = CancelToken();
    final pending = [
      for (var i = 0; i < 4; i++)
        pool.run(evalJs('java.ajax(base + "/slow")', globals: {'base': f.base}), cancelToken: token),
    ];
    await Future<void>.delayed(const Duration(milliseconds: 300));
    token.cancel();
    final watch = Stopwatch()..start();
    for (final future in pending) {
      await _expectError<TaskCancelledException>(future);
    }
    _expect(watch.elapsedMilliseconds < 100, '取消用时 ${watch.elapsedMilliseconds}ms');
    return '2 个阻塞中 + 2 个排队中，${watch.elapsedMilliseconds}ms 内全部取消';
  },
  '取消：穿透嵌套的 java.getString': (f) async {
    final pool = f.pool();
    final token = CancelToken();
    final pending = pool.run(
      evalJs('try { java.getString("@js:while (true) {}") } catch (e) {} java.log("continued")'),
      cancelToken: token,
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    token.cancel();
    await _expectError<TaskCancelledException>(pending);
    final logs = await pool.run(takeLogs());
    _expect(logs.isEmpty, '外层 JS 在 catch 之后继续执行了：$logs');
    return '内层中止穿透到外层';
  },
  '取消：卡在 JS 调用的 Dart 宿主函数里，宽限期后被放弃，进程不崩溃': (f) async {
    final pool = f.pool(grace: const Duration(milliseconds: 200));
    final token = CancelToken();
    final pending = pool.run(evalJs('java.spin(1500)'), cancelToken: token);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    token.cancel();
    await _expectError<TaskCancelledException>(pending);
    final watch = Stopwatch()..start();
    final value = await pool.run(evalJs('"replacement"'));
    final takeoverMs = watch.elapsedMilliseconds;
    _expect(value == 'replacement' && takeoverMs < 1500, 'got $value，用时 ${takeoverMs}ms');
    // 等被放弃的 worker 算完、自行退出
    await Future<void>.delayed(const Duration(seconds: 2));
    _expect(await pool.run(evalJs('"alive"')) == 'alive', '池不可用');
    return '新 worker ${takeoverMs}ms 后接手';
  },
  '规则引擎：真实书源四条链路（外网）': (f) => runRuleEngineChains(),
};

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<List<CheckResult>> runSpikeChecks({void Function(CheckResult)? onResult}) async {
  final results = <CheckResult>[];
  for (final MapEntry(key: name, value: check) in _checks.entries) {
    final fixture = await _Fixture.start();
    final watch = Stopwatch()..start();
    CheckResult result;
    try {
      final detail = await check(fixture).timeout(const Duration(seconds: 30));
      result = CheckResult(name, true, detail, watch.elapsed);
    } catch (e) {
      result = CheckResult(name, false, '$e', watch.elapsed);
    } finally {
      await fixture.close();
    }
    results.add(result);
    onResult?.call(result);
  }
  return results;
}

/// 测量 worker 的内存成本：依次让 1 到 [size] 个 worker 各建好 QuickJS 引擎，记录进程 RSS；
/// 最后让每个 worker 跑一段接近解析书页的 JS，再记录一次。
Future<String> measureWorkerRss({int size = 4}) async {
  final fixture = await _Fixture.start();
  final pool = fixture.pool(size: size);
  Future<int> settledRss() async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    return ProcessInfo.currentRss;
  }

  String mb(int bytes) => (bytes / (1 << 20)).toStringAsFixed(1);
  try {
    final baseline = await settledRss();
    final lines = ['基线 ${mb(baseline)}MB'];
    var previous = baseline;
    for (var workers = 1; workers <= size; workers++) {
      // 宿主请求挂起 300ms，保证这批任务同时占住 workers 个 worker
      await Future.wait([
        for (var i = 0; i < workers; i++) pool.run(evalJs('java.getVerificationCode("x")')),
      ]);
      _expect(pool.availableWorkers == workers, 'worker 数 ${pool.availableWorkers}');
      final rss = await settledRss();
      lines.add('$workers 个 worker ${mb(rss)}MB（+${mb(rss - previous)}MB）');
      previous = rss;
    }
    // 负载放在函数作用域里，结束后可以回收；跑两轮，看内存是否继续增长
    var loaded = previous;
    for (var round = 1; round <= 2; round++) {
      final counts = await Future.wait([
        for (var i = 0; i < size; i++)
          pool.run(evalJs('''
            (function () {
              var items = [];
              for (var i = 0; i < 20000; i++) items.push({title: "第" + i + "章", url: "/book/" + i + ".html"});
              return JSON.stringify(items).match(/第\\d+章/g).length;
            })()
          ''')),
      ]);
      _expect(counts.every((count) => count == 20000), 'got $counts');
      final rss = await settledRss();
      lines.add('第 $round 轮：每个 worker 解析约 1MB 数据后 ${mb(rss)}MB（+${mb(rss - loaded)}MB）');
      loaded = rss;
    }
    lines.add('平均每个 worker：空闲 ${mb((previous - baseline) ~/ size)}MB，负载后 ${mb((loaded - baseline) ~/ size)}MB');
    return lines.join('\n');
  } finally {
    await fixture.close();
  }
}
