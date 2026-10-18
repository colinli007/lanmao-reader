import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:blocking_bridge/blocking_bridge.dart';
import 'package:rule_engine/rule_engine.dart';
import 'package:rule_engine/src/core/source_task.dart';
import 'package:rule_engine/src/host/rate_limiter.dart';
import 'package:rule_engine/src/net/public_suffix.dart';
import 'package:rule_engine/src/request/analyze_url.dart';
import 'package:rule_engine/src/request/response_decoder.dart';
import 'package:test/test.dart';

// source-request 规格里网络、Cookie、限速的场景：本地 HTTP 服务 + worker 池
void main() {
  late HttpServer server;
  late String base;
  final requestTimes = <String, List<DateTime>>{};

  setUp(() async {
    requestTimes.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((request) async {
      final path = request.uri.path;
      (requestTimes[path] ??= []).add(DateTime.now());
      final response = request.response..headers.contentType = ContentType('text', 'html', charset: 'utf-8');
      switch (path) {
        case '/slow':
          await Future<void>.delayed(Duration(milliseconds: int.parse(request.uri.queryParameters['ms'] ?? '10000')));
          response.write('slow ${request.uri.query}');
        case '/redirect':
          response
            ..statusCode = 302
            ..headers.set('location', '/book/1/');
        case '/post-redirect':
          response
            ..statusCode = 302
            ..headers.set('location', '/echo');
        case '/missing':
          response
            ..statusCode = 404
            ..write('<p>找不到</p>');
        case '/login':
          response.headers.add('set-cookie', 'sid=1; Path=/');
          response.headers.add('set-cookie', 'keep=2; Max-Age=3600');
          response.write('ok');
        case '/go':
          response
            ..statusCode = 302
            ..headers.set('location', '/book/1');
        case '/forbidden':
          response
            ..statusCode = 403
            ..write('no');
        case '/set-cookies':
          response.headers.add('set-cookie', 'a=1; Expires=Wed, 21 Oct 2037 07:28:00 GMT; Path=/');
          response.headers.add('set-cookie', 'b=2; Expires=Thu, 22 Oct 2037 07:28:00 GMT');
          response.write('ok');
        case '/echo':
          final body = await utf8.decodeStream(request);
          response.write('${request.method}|${request.headers.value('cookie') ?? ''}|$body');
        default:
          response.write('<a href="2.html">x</a>');
      }
      await response.close();
    });
  });

  tearDown(() => server.close(force: true));

  group('网络请求在主 isolate 上执行', () {
    test('取消时中断请求', () async {
      final host = RuleHost();
      final cancelled = Completer<void>();
      final watch = Stopwatch()..start();
      final future = host.execute(HttpRequest(url: '$base/slow?ms=10000', sourceUrl: base), cancelled: cancelled.future);
      Timer(const Duration(milliseconds: 200), cancelled.complete);
      await expectLater(future, throwsA(anything));
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('任务被取消时提交方立即收到取消错误', () async {
      final host = RuleHost();
      final pool = WorkerPool(host.handle, size: 1);
      addTearDown(pool.close);
      final token = CancelToken();
      final future = pool.run(_fetch('$base/slow?ms=10000'), cancelToken: token);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final watch = Stopwatch()..start();
      token.cancel();
      await expectLater(future, throwsA(isA<TaskCancelledException>()));
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('整批并发，结果按提交顺序', () async {
      final pool = WorkerPool(RuleHost().handle, size: 1);
      addTearDown(pool.close);
      final watch = Stopwatch()..start();
      final bodies = await pool.run(_fetchAll([for (var i = 1; i <= 5; i++) '$base/slow?ms=1000&p=$i']));
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(bodies, [for (var i = 1; i <= 5; i++) 'slow ms=1000&p=$i']);
    });
  });

  group('响应处理', () {
    test('跟随重定向，最终地址是重定向之后的地址', () async {
      final result = await RuleHost().execute(HttpRequest(url: '$base/redirect', sourceUrl: base));
      expect(result.url, '$base/book/1/');
      expect(decodeResponseBody(result), '<a href="2.html">x</a>');
    });

    test('POST 遇到 302 改成不带请求体的 GET', () async {
      final result = await RuleHost().execute(
        HttpRequest(url: '$base/post-redirect', method: 'POST', body: 'q=1', sourceUrl: base, headers: const {'Content-Type': 'application/x-www-form-urlencoded'}),
      );
      expect(decodeResponseBody(result), 'GET||');
    });

    test('404 照常返回', () async {
      final result = await RuleHost().execute(HttpRequest(url: '$base/missing', sourceUrl: base));
      expect(result.statusCode, 404);
      expect(decodeResponseBody(result), '<p>找不到</p>');
    });

    test('非 2xx 时按 retry 重试', () async {
      await RuleHost().execute(HttpRequest(url: '$base/missing', sourceUrl: base, retry: 2));
      expect(requestTimes['/missing'], hasLength(3));
    });

    test('POST 请求体按 UTF-8 发送', () async {
      final result = await RuleHost().execute(HttpRequest(url: '$base/echo', method: 'POST', body: '{"k":"三体"}', sourceUrl: base));
      expect(decodeResponseBody(result), 'POST||{"k":"三体"}');
    });
  });

  group('跨 worker 共享 Cookie', () {
    test('登录态在 worker 之间共享', () async {
      final pool = WorkerPool(RuleHost().handle, size: 2);
      addTearDown(pool.close);
      // worker A 登录后继续占着；worker B 的请求带上 A 收到的 Cookie
      final first = pool.run(_fetchAll(['$base/login', '$base/slow?ms=1500'], cookieJar: true));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final second = await pool.run(_fetch('$base/echo', cookieJar: true));
      expect(second, 'GET|keep=2; sid=1|');
      await first;
    });

    test('没开 CookieJar 时不保存 Set-Cookie，但仍带上已有的 Cookie', () async {
      final host = RuleHost();
      await host.execute(HttpRequest(url: '$base/login', sourceUrl: base));
      host.cookieStore.setCookie(base, 'a=1');
      final result = await host.execute(HttpRequest(url: '$base/echo', sourceUrl: base, headers: const {'Cookie': 'a=9; b=2'}));
      // 请求头里已有的值优先
      expect(decodeResponseBody(result), 'GET|a=9; b=2|');
    });

    test('子域名共享，公共后缀不合并', () {
      final store = CookieStore()..saveResponse(Uri.parse('https://www.a.com/'), ['x=1']);
      expect(store.getCookie('https://m.a.com/b'), 'x=1');
      store.saveResponse(Uri.parse('https://x.com.cn/'), ['y=2']);
      expect(store.getCookie('https://y.com.cn/'), '');
      expect(store.getCookie('https://www.x.com.cn/'), 'y=2');
    });

    test('只存名和值，空白值丢弃，会话 Cookie 优先', () {
      final store = CookieStore()
        ..saveResponse(Uri.parse('https://a.com/'), ['p=1; Expires=Wed, 21 Oct 2099 07:28:00 GMT', 's=1', 'e='])
        ..saveResponse(Uri.parse('https://a.com/'), ['p=2']);
      expect(store.getCookie('https://a.com/'), 'p=2; s=1');
      // 删除 Cookie（空值）不生效
      store.saveResponse(Uri.parse('https://a.com/'), ['s=; Max-Age=0']);
      expect(store.getCookie('https://a.com/'), 'p=2; s=1');
    });

    test('Domain 属性不匹配或是公共后缀时拒绝', () {
      final store = CookieStore()
        ..saveResponse(Uri.parse('https://a.com/'), ['x=1; Domain=b.com', 'y=1; Domain=com', 'z=1; Domain=.a.com']);
      expect(store.getCookie('https://a.com/'), 'z=1');
    });

    test('初始的持久 Cookie 随请求发送', () async {
      final host = RuleHost(cookieStore: CookieStore(persistent: {cookieDomain(base): 'sid=7'}));
      final result = await host.execute(HttpRequest(url: '$base/echo', sourceUrl: base));
      expect(decodeResponseBody(result), 'GET|sid=7|');
    });

    test('持久 Cookie 每次改写回调一次新值，只改会话 Cookie 时不回调', () {
      final changes = <(String, String?)>[];
      final store = CookieStore(persistent: {'a.com': 'p=0'}, onPersistentChanged: (domain, cookie) => changes.add((domain, cookie)));
      store.saveResponse(Uri.parse('https://www.a.com/'), ['s=1']);
      expect(changes, isEmpty);
      store.saveResponse(Uri.parse('https://www.a.com/'), ['p=1; Max-Age=60', 's=2']);
      store.setCookie('https://b.com', 'x=1');
      store.replaceCookie('https://m.b.com', 'y=2');
      store.removeCookie('https://a.com');
      expect(changes, [('a.com', 'p=1'), ('b.com', 'x=1'), ('b.com', 'x=1; y=2'), ('a.com', null)]);
      expect(store.getCookie('https://a.com'), '');
    });
  });

  group('书源级状态', () {
    test('过期时间，saveTime 为 0 不过期', () {
      var now = DateTime(2026);
      final store = MemorySourceStore(now: () => now);
      final cookies = CookieStore();
      runStoreRequest(const StoreRequest(StoreOp.put, 'k', value: 'v', saveSeconds: 10), store, cookies);
      runStoreRequest(const StoreRequest(StoreOp.put, 'forever', value: 'f'), store, cookies);
      now = now.add(const Duration(seconds: 9));
      expect(runStoreRequest(const StoreRequest(StoreOp.get, 'k'), store, cookies), 'v');
      now = now.add(const Duration(seconds: 1));
      expect(runStoreRequest(const StoreRequest(StoreOp.get, 'k'), store, cookies), isNull);
      now = now.add(const Duration(days: 3650));
      expect(runStoreRequest(const StoreRequest(StoreOp.get, 'forever'), store, cookies), 'f');
      runStoreRequest(const StoreRequest(StoreOp.delete, 'forever'), store, cookies);
      expect(runStoreRequest(const StoreRequest(StoreOp.get, 'forever'), store, cookies), isNull);
    });

    test('内存值是任意 JSON 值', () {
      final store = MemorySourceStore();
      final cookies = CookieStore();
      runStoreRequest(const StoreRequest(StoreOp.putMemory, 'm', value: {'a': [1, 2]}), store, cookies);
      expect(runStoreRequest(const StoreRequest(StoreOp.getMemory, 'm'), store, cookies), {'a': [1, 2]});
      expect(runStoreRequest(const StoreRequest(StoreOp.get, 'm'), store, cookies), isNull);
    });

    test('replaceCookie 按名合并，setCookie 覆盖，removeCookie 全删', () {
      final store = MemorySourceStore();
      final cookies = CookieStore();
      Object? run(StoreOp op, String key, [String? value]) => runStoreRequest(StoreRequest(op, key, value: value), store, cookies);
      run(StoreOp.setCookie, 'https://www.a.com', 'x=1; y=2');
      run(StoreOp.replaceCookie, 'https://m.a.com/path', 'y=3; z=4');
      expect(run(StoreOp.getCookie, 'https://a.com'), 'x=1; y=3; z=4');
      run(StoreOp.setCookie, 'https://a.com', 'w=0');
      expect(run(StoreOp.getCookie, 'https://a.com'), 'w=0');
      run(StoreOp.removeCookie, 'https://www.a.com');
      expect(run(StoreOp.getCookie, 'https://a.com'), '');
    });

    test('不是 http 地址时整段文本就是键', () {
      final store = MemorySourceStore();
      final cookies = CookieStore();
      runStoreRequest(const StoreRequest(StoreOp.setCookie, 'abc', value: 'k=v'), store, cookies);
      expect(runStoreRequest(const StoreRequest(StoreOp.getCookie, 'abc'), store, cookies), 'k=v');
      expect(runStoreRequest(const StoreRequest(StoreOp.getCookie, 'https://abc.com'), store, cookies), '');
    });

    test('不同 worker 读到同一份；日志带书源地址实时到达接收方', () async {
      final logs = <SourceLog>[];
      final host = RuleHost(onLog: logs.add);
      final pool = WorkerPool(host.handle, size: 2);
      addTearDown(pool.close);
      await pool.run(_storePut('k', 'v'));
      final reads = await Future.wait([pool.run(_storeGet('k')), pool.run(_storeGet('k'))]);
      expect(reads, ['v', 'v']);
      await pool.run(_log('https://a.com', 'ruleSearch.name', '3'));
      expect(logs.single.sourceUrl, 'https://a.com');
      expect(logs.single.field, 'ruleSearch.name');
      expect(logs.single.message, '3');
    });

    test('登录头叠加到请求头里，任务里写入后立即生效', () {
      final env = _MemoryEnvironment();
      final task = SourceTask(env, _source({'header': '{"Referer":"https://a.com/","X-A":"1"}'}));
      expect(buildSourceRequest(task, '/x').http.headers.containsKey('Authorization'), isFalse);
      task.putLoginHeader('{"Authorization":"Bearer t","X-A":"2","Cookie":"sid=9"}');
      final headers = buildSourceRequest(task, '/x').http.headers;
      expect(headers['Authorization'], 'Bearer t');
      expect(headers['X-A'], '2');
      expect(headers['Referer'], 'https://a.com/');
      expect(env.cookies.getCookie('https://a.com'), 'sid=9');
      // 另一个任务从书源级状态里读到同一个登录头
      expect(buildSourceRequest(SourceTask(env, task.source), '/x').http.headers['Authorization'], 'Bearer t');
      task.removeLoginHeader();
      expect(buildSourceRequest(task, '/x').http.headers.containsKey('Authorization'), isFalse);
      expect(env.cookies.getCookie('https://a.com'), '');
    });
  });

  group('直连请求', () {
    Future<HttpResult> direct(String path, {String method = 'GET'}) =>
        RuleHost().execute(HttpRequest(url: '$base$path', method: method, sourceUrl: base, direct: true));

    test('不跟随重定向，拿到 Location', () async {
      final result = await direct('/go');
      expect(result.statusCode, 302);
      expect(result.headers['location'], '/book/1');
    });

    test('状态码 >= 400 时报错', () async {
      await expectLater(direct('/forbidden'), throwsA(isA<HttpException>()));
    });

    test('不带书源域名的 Cookie', () async {
      final host = RuleHost();
      host.cookieStore.setCookie(base, 'sid=1');
      final result = await host.execute(HttpRequest(url: '$base/echo', sourceUrl: base, direct: true));
      expect(utf8.decode(result.body), 'GET||');
    });

    test('Set-Cookie 含逗号日期时逐条保留，并能经 worker 传回', () async {
      final result = await direct('/set-cookies');
      expect(result.setCookies, [
        'a=1; Expires=Wed, 21 Oct 2037 07:28:00 GMT; Path=/',
        'b=2; Expires=Thu, 22 Oct 2037 07:28:00 GMT',
      ]);
      final pool = WorkerPool(RuleHost().handle, size: 1);
      addTearDown(pool.close);
      expect(await pool.run(_setCookies('$base/set-cookies')), hasLength(2));
    });

    test('单次请求超时', () async {
      final watch = Stopwatch()..start();
      await expectLater(
        RuleHost().execute(HttpRequest(url: '$base/slow?ms=5000', sourceUrl: base, timeout: const Duration(milliseconds: 300))),
        throwsA(isA<TimeoutException>()),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });
  });

  group('书源限速', () {
    test('间隔限速：两个 worker 同时请求', () async {
      final pool = WorkerPool(RuleHost().handle, size: 2);
      addTearDown(pool.close);
      await Future.wait([
        pool.run(_fetch('$base/echo', rate: '500')),
        pool.run(_fetch('$base/echo', rate: '500')),
      ]);
      final times = requestTimes['/echo']!..sort();
      expect(times[1].difference(times[0]), greaterThanOrEqualTo(const Duration(milliseconds: 450)));
    });

    test('a/b：每 b 毫秒最多 a 次', () {
      var now = DateTime(2026);
      final limiter = RateLimiter(clock: () => now);
      expect(limiter.acquire('s', '2/1000'), completes);
      expect(limiter.acquire('s', '2/1000'), completes);
      // 第三次要等到窗口结束：用一个不会走到的时钟检查没有立即完成
      var done = false;
      unawaited(limiter.acquire('s', '2/1000').then((_) => done = true));
      expect(done, isFalse);
      now = now.add(const Duration(seconds: 1));
    });

    test('为空或 0 时不限速', () async {
      final limiter = RateLimiter();
      final watch = Stopwatch()..start();
      for (var i = 0; i < 5; i++) {
        await limiter.acquire('s', '0');
        await limiter.acquire('t', null);
      }
      expect(watch.elapsedMilliseconds, lessThan(100));
    });
  });
}

String Function() _fetch(String url, {bool cookieJar = false, String? rate}) => () {
  final env = const WorkerRuleEnvironment();
  final origin = Uri.parse(url).origin;
  return decodeResponseBody(
    env.fetch(HttpRequest(url: url, sourceUrl: origin, enabledCookieJar: cookieJar, concurrentRate: rate)),
  );
};

List<String> Function() _fetchAll(List<String> urls, {bool cookieJar = false}) => () {
  final env = const WorkerRuleEnvironment();
  final requests = [
    for (final url in urls) HttpRequest(url: url, sourceUrl: Uri.parse(url).origin, enabledCookieJar: cookieJar),
  ];
  // 登录用例需要先后执行：第一个请求单独发
  if (cookieJar && requests.length == 2) {
    return [decodeResponseBody(env.fetch(requests[0])), decodeResponseBody(env.fetch(requests[1]))];
  }
  return env.fetchAll(requests).map(decodeResponseBody).toList();
};

String? Function() _storeGet(String key) =>
    () => const WorkerRuleEnvironment().store(StoreRequest(StoreOp.get, key)) as String?;

void Function() _storePut(String key, String value) =>
    () => const WorkerRuleEnvironment().store(StoreRequest(StoreOp.put, key, value: value));

void Function() _log(String sourceUrl, String field, String message) =>
    () => const WorkerRuleEnvironment().log(SourceLog(sourceUrl: sourceUrl, field: field, message: message));

List<String> Function() _setCookies(String url) => () =>
    const WorkerRuleEnvironment().fetch(HttpRequest(url: url, sourceUrl: url, direct: true)).setCookies;

BookSource _source(Map<String, Object?> extra) =>
    loadBookSources(jsonEncode({'bookSourceUrl': 'https://a.com', 'bookSourceName': 'A', ...extra})).sources.single;

/// 只有书源级状态的环境：登录头的用例不发请求。
final class _MemoryEnvironment implements RuleEnvironment {
  final MemorySourceStore sourceStore = MemorySourceStore();
  final CookieStore cookies = CookieStore();

  @override
  Object? store(StoreRequest request) => runStoreRequest(request, sourceStore, cookies);

  @override
  void log(SourceLog log) {}

  @override
  HttpResult fetch(HttpRequest request) => throw UnimplementedError();

  @override
  List<HttpResult> fetchAll(List<HttpRequest> requests) => throw UnimplementedError();

  @override
  void checkCancelled() {}

  @override
  Pointer<Int32> get abortSignal => throw UnimplementedError();
}
