import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:blocking_bridge/blocking_bridge.dart';
import 'package:rule_engine/rule_engine.dart';
import 'package:rule_engine/src/host/cookie_store.dart';
import 'package:rule_engine/src/host/rate_limiter.dart';
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
