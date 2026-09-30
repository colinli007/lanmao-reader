/// 纯 Flutter 路线的前置验证项。集成测试和演示界面共用这一份。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:quickjs_ng_ffi/quickjs_ng_ffi.dart';

import 'js_worker.dart';

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
  final List<JsWorker> workers = [];

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

  Future<JsWorker> worker({Duration requestTimeout = const Duration(seconds: 15)}) async {
    final worker = await JsWorker.spawn(_handleHostRequest, requestTimeout: requestTimeout);
    workers.add(worker);
    return worker;
  }

  Future<void> close() async {
    for (final worker in workers) {
      worker.dispose();
    }
    await server.close(force: true);
  }
}

/// 主 isolate 上的宿主实现：全部是普通的异步代码。
Future<Object?> _handleHostRequest(String op, Object? payload) async {
  final args = payload as List<Object?>;
  switch (op) {
    case 'http.get':
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      try {
        final request = await client.getUrl(Uri.parse(args[0] as String));
        final response = await request.close();
        return await response.transform(const Utf8Decoder(allowMalformed: true)).join();
      } finally {
        client.close(force: true);
      }
    case 'ui.verificationCode':
      // 模拟弹出验证码输入框、等用户输入：主 isolate 异步等待一段时间后给出结果
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return 'code-for-${args[0]}';
    default:
      throw UnsupportedError(op);
  }
}

final Map<String, _Check> _checks = {
  '工作 isolate 里求值': (f) async {
    final worker = await f.worker();
    final value = await worker.run('[1, 2, 3].map(x => x * 2).join(",")');
    _expect(value == '2,4,6', 'got $value');
    return '$value';
  },
  'JS 同步 ajax（本地 HTTP）': (f) async {
    final worker = await f.worker();
    final value = await worker.run('var html = java.ajax(base + "/hello"); html.length + ":" + html',
        globals: {'base': f.base});
    _expect('$value'.endsWith('你好 /hello'), 'got $value');
    return '$value';
  },
  'JS 同步 ajax（HTTPS 外网）': (f) async {
    final worker = await f.worker();
    final value = await worker.run('java.ajax("https://example.com").indexOf("Example Domain") >= 0');
    _expect(value == true, 'got $value');
    return 'example.com 正文包含 Example Domain';
  },
  '同步等待「用户输入」（验证码 / WebView 同一机制）': (f) async {
    final worker = await f.worker();
    final watch = Stopwatch()..start();
    final value = await worker.run('java.getVerificationCode("https://a.com/captcha.png")');
    _expect(value == 'code-for-https://a.com/captcha.png', 'got $value');
    _expect(watch.elapsedMilliseconds >= 300, '等待时间不足 ${watch.elapsedMilliseconds}ms');
    return '$value';
  },
  '嵌套：规则回调里的 JS 再同步 ajax': (f) async {
    final worker = await f.worker();
    final value = await worker.run(
      'java.getString("@js:java.ajax(base + \'/hello\').toUpperCase()")',
      globals: {'base': f.base},
    );
    _expect('$value'.contains('/HELLO'), 'got $value');
    return '$value';
  },
  '宿主请求超时：JS 收到异常，可 catch': (f) async {
    final worker = await f.worker(requestTimeout: const Duration(milliseconds: 500));
    final watch = Stopwatch()..start();
    final value = await worker.run(
      'try { java.ajax(base + "/slow"); "no error" } catch (e) { "caught: " + e.message }',
      globals: {'base': f.base},
    );
    _expect('$value'.contains('超时'), 'got $value');
    _expect(watch.elapsedMilliseconds < 2500, '没有按超时返回：${watch.elapsedMilliseconds}ms');
    return '$value';
  },
  '工作 isolate 阻塞时主 isolate 不卡': (f) async {
    final worker = await f.worker();
    var ticks = 0;
    final timer = Timer.periodic(const Duration(milliseconds: 50), (_) => ticks++);
    await worker.run('java.ajax(base + "/slow")', globals: {'base': f.base});
    timer.cancel();
    // 3 秒内理论上有 60 次，留足余量
    _expect(ticks >= 40, '主 isolate 定时器只触发了 $ticks 次');
    return '阻塞 3 秒期间主 isolate 定时器触发 $ticks 次';
  },
  '两个工作 isolate 并发阻塞': (f) async {
    final a = await f.worker();
    final b = await f.worker();
    final watch = Stopwatch()..start();
    final results = await Future.wait([
      a.run('java.ajax(base + "/slow")', globals: {'base': f.base}),
      b.run('java.ajax(base + "/slow")', globals: {'base': f.base}),
    ]);
    final ms = watch.elapsedMilliseconds;
    _expect(results.every((r) => '$r'.contains('/slow')), 'got $results');
    _expect(ms < 5500, '串行了：${ms}ms');
    return '两个 3 秒请求共耗时 ${ms}ms';
  },
  '释放阻塞中的工作 isolate 不会卡住': (f) async {
    final worker = await f.worker();
    final pending = worker.run('java.ajax(base + "/slow")', globals: {'base': f.base});
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final watch = Stopwatch()..start();
    worker.dispose();
    try {
      await pending;
    } on StateError {
      // 预期：任务随 worker 一起被取消
    }
    return 'dispose 返回用时 ${watch.elapsedMilliseconds}ms';
  },
  '压力：4 个工作 isolate 各 300 轮注入变量 + 求值 + 阻塞调用': (f) async {
    final workers = [for (var i = 0; i < 4; i++) await f.worker()];
    final watch = Stopwatch()..start();
    await Future.wait([
      for (final (index, worker) in workers.indexed)
        () async {
          for (var round = 0; round < 300; round++) {
            final value = await worker.run(
              'java.ajax(base + "/hello").length + n',
              globals: {'base': f.base, 'n': round},
            );
            _expect(value == 9 + round, 'worker $index round $round got $value');
          }
        }(),
    ]);
    return '1200 次共 ${watch.elapsedMilliseconds}ms';
  },
  'JS 死循环按超时中断': (f) async {
    final worker = await f.worker();
    try {
      await worker.run('while (true) {}', timeout: const Duration(milliseconds: 300));
      throw StateError('没有中断');
    } on JsException catch (e) {
      _expect(e.message.contains('interrupted'), e.message);
    }
    final value = await worker.run('"still alive"');
    _expect(value == 'still alive', 'got $value');
    return '中断后引擎仍可用';
  },
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
