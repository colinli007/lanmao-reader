import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:blocking_bridge/blocking_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/online/batch.dart';
import 'package:novel_reader/online/engine_stack.dart';
import 'package:novel_reader/online/source_engine.dart';
import 'package:rule_engine/rule_engine.dart';

/// book-search「等网络的书源不妨碍其它书源」「慢的书源按超时失败」：真实的 worker 池，请求函数是假的。
/// 失败的用例里书源要执行 JS，需要 QUICKJS_NG_FFI_LIB 指向开发机上编出来的 quickjs 动态库（见 README）。
void main() {
  late List<String> logs;
  late WorkerPool pool;

  setUp(() {
    logs = [];
    pool = WorkerPool(RuleHost(onLog: (log) => logs.add(log.message)).handle, size: EngineStack.poolSize);
  });
  tearDown(() => pool.close());

  BookSource source(int i, [Map<String, Object?> extra = const {}]) => loadBookSources(
    jsonEncode({
      'bookSourceUrl': 'https://s$i.com',
      'bookSourceName': '书源$i',
      'searchUrl': '/s',
      'ruleSearch': {'bookList': 'tag.li', 'name': 'text', 'bookUrl': 'text'},
      ...extra,
    }),
  ).sources.single;

  HttpResult ok(HttpRequest request) =>
      HttpResult(statusCode: 200, url: request.url, body: Uint8List.fromList(utf8.encode('<li>${request.url}</li>')));

  test('12 个书源的网站都要 2 秒才响应，4 秒内全部完成', () async {
    final engine = PoolSourceEngine(pool, (request, {cancelled}) async {
      await Future<void>.delayed(const Duration(seconds: 2));
      return ok(request);
    });
    final batch = Batch();
    final watch = Stopwatch()..start();
    final results = await Future.wait([for (var i = 0; i < 12; i++) engine.search(source(i), '三体', batch)]);
    expect(watch.elapsed, lessThan(const Duration(seconds: 4)));
    expect(results.map((books) => books.single.name), [for (var i = 0; i < 12; i++) 'https://s$i.com/s']);
  });

  test('40 个书源同时搜，同时在途的请求最多 32 个', () async {
    var inFlight = 0;
    var peak = 0;
    final engine = PoolSourceEngine(pool, (request, {cancelled}) async {
      peak = (++inFlight) > peak ? inFlight : peak;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      inFlight--;
      return ok(request);
    });
    final batch = Batch();
    await Future.wait([for (var i = 0; i < 40; i++) engine.search(source(i), '三体', batch)]);
    expect(peak, 32);
  });

  test('响应要 3 秒的书源在 1 秒的超时后失败，连接被关闭，其它书源不受影响', () async {
    var slowClosed = false;
    final engine = PoolSourceEngine(pool, searchTimeout: const Duration(seconds: 1), (request, {cancelled}) async {
      if (request.sourceUrl == 'https://s0.com') {
        unawaited(cancelled?.then((_) => slowClosed = true));
        await Future<void>.delayed(const Duration(seconds: 3));
      }
      return ok(request);
    });
    final batch = Batch();
    final watch = Stopwatch()..start();
    final slow = engine.search(source(0), '三体', batch);
    final others = Future.wait([for (var i = 1; i < 6; i++) engine.search(source(i), '三体', batch)]);
    await expectLater(
      slow,
      throwsA(isA<TaskTimeoutException>().having((e) => e.timeout, 'timeout', const Duration(seconds: 1))),
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    expect(slowClosed, isTrue);
    expect((await others).map((books) => books.single.name), hasLength(5));
  });

  test('请求失败时是网络错误，原因和原始异常相同，不再提交第二段', () async {
    const error = SocketException('Connection refused');
    final engine = PoolSourceEngine(pool, (request, {cancelled}) async => throw error);
    // 第二段执行 loginCheckJs 时会写日志
    final s = source(0, {'loginCheckJs': "java.log('第二段'); result"});
    await expectLater(
      engine.search(s, '三体', Batch()),
      throwsA(isA<HostCallException>().having((e) => e.message, 'message', error.toString())),
    );
    expect(logs, isEmpty);
  });

  test('停止后，等网络的书源在 100 毫秒内以取消结束', () async {
    // 请求一直不返回，也不理会 cancelled：停止不等请求或关连接的过程
    final allWaiting = Completer<void>();
    var waiting = 0;
    final engine = PoolSourceEngine(pool, (request, {cancelled}) {
      if (++waiting == 5) allWaiting.complete();
      return Completer<HttpResult>().future;
    });
    final batch = Batch();
    final searches = [for (var i = 0; i < 5; i++) engine.search(source(i), '三体', batch)];
    await allWaiting.future;
    final watch = Stopwatch()..start();
    batch.stop();
    await Future.wait([for (final search in searches) expectLater(search, throwsA(isA<TaskCancelledException>()))]);
    expect(watch.elapsed, lessThan(const Duration(milliseconds: 100)));
  });
}
