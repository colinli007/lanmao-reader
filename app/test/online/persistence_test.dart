import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanmao_reader/online/engine_stack.dart';
import 'package:lanmao_reader/online/persistent_source_store.dart';
import 'package:lanmao_reader/storage/database.dart';
import 'package:lanmao_reader/storage/write_queue.dart';
import 'package:rule_engine/rule_engine.dart';

/// app-storage「书源级状态读写即时可见」「持久 Cookie」：重开数据库模拟重启。
/// 需要 QUICKJS_NG_FFI_LIB 指向开发机上编出来的 quickjs 动态库（见 README）。
void main() {
  late Directory dir;
  late HttpServer server;
  late String base;
  final requests = <({String path, String? cookie, String? authorization})>[];

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('app');
    requests.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((request) {
      requests.add((
        path: request.uri.path,
        cookie: request.headers.value('cookie'),
        authorization: request.headers.value('authorization'),
      ));
      final response = request.response;
      if (request.uri.path == '/login') {
        response.headers.add('set-cookie', 'sid=1; Max-Age=86400');
        response.headers.add('set-cookie', 'tmp=1');
      }
      response
        ..headers.contentType = ContentType.html
        ..write('<ul><li>x</li></ul>')
        ..close();
    });
  });
  tearDown(() async {
    await server.close(force: true);
    dir.deleteSync(recursive: true);
  });

  AppDatabase openDb() => AppDatabase(NativeDatabase(File('${dir.path}/app.sqlite')));

  BookSource source(String searchUrl) => loadBookSources('''{
    "bookSourceUrl": "$base", "bookSourceName": "测试", "searchUrl": ${_quote(searchUrl)},
    "ruleSearch": {"bookList": "tag.li", "name": "text", "bookUrl": "text"}
  }''').sources.single;

  /// 启动一次 app 的引擎部分，执行 [searchUrls] 各一次搜索，然后像退出 app 一样等落盘完成后关闭。
  Future<List<String>> run(List<String> searchUrls, {DateTime Function()? now}) async {
    final db = openDb();
    final logs = <String>[];
    final queue = WriteQueue(onError: (e) => fail('落盘失败：$e'));
    final engine = await EngineStack.open(db, queue, onLog: (log) => logs.add(log.message), poolSize: 1, now: now);
    try {
      for (final url in searchUrls) {
        await engine.pool.run(searchTask(source(url), 'k'));
      }
    } finally {
      engine.close();
      await queue.flush();
      await db.close();
    }
    return logs;
  }

  test('书源变量和登录头在重启后仍在', () async {
    await run([r'''@js:source.setVariable('x'); source.putLoginHeader('{"Authorization":"t"}'); '/a' ''']);
    final logs = await run([r'''@js:java.log(source.getVariable()); '/b' ''']);
    expect(logs, ['x']);
    expect(requests.last, (path: '/b', cookie: null, authorization: 't'));
  });

  test('cache.put 的值重启后未过期时读得到，过期后读不到', () async {
    var now = DateTime(2026);
    await run([r'''@js:cache.put('k', 'v', 600); cache.put('short', 'v', 1); cache.putMemory('m', 'v'); '/a' '''], now: () => now);
    now = now.add(const Duration(minutes: 1));
    final logs = await run([r'''@js:java.log([cache.get('k'), cache.get('short'), cache.getFromMemory('m')].join()); '/b' '''], now: () => now);
    // 未过期的 k 读得到；过期的 short 和只在内存里的 m 都是 null（join 成空串）
    expect(logs, ['v,,']);
  });

  test('持久 Cookie 跨重启，会话 Cookie 不跨重启，删除后不恢复', () async {
    await run(['/login']);
    await run(['/a']);
    expect(requests.last.cookie, 'sid=1');
    await run([r'''@js:cookie.removeCookie(source.getKey()); '/b' ''']);
    await run(['/c']);
    expect(requests.last, (path: '/c', cookie: null, authorization: null));
  });

  test('putMemory 的值不落盘，过期时间按写入时的时钟计算', () async {
    var now = DateTime(2026);
    final db = openDb();
    final queue = WriteQueue(onError: (e) => fail('$e'));
    final store = await PersistentSourceStore.load(db, queue, now: () => now);
    store
      ..put('k', 'v', ttl: const Duration(seconds: 10))
      ..putMemory('m', 'v');
    await queue.flush();
    now = now.add(const Duration(seconds: 9));
    final reloaded = await PersistentSourceStore.load(db, queue, now: () => now);
    expect((reloaded.get('k'), reloaded.getMemory('m')), ('v', null));
    now = now.add(const Duration(seconds: 1));
    expect(reloaded.get('k'), isNull);
    await db.close();
  });
}

String _quote(String text) => '"${text.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
