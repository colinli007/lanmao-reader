import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanmao_reader/reader/content_images.dart';

import '../support/fixtures.dart';
import '../support/test_app.dart';

/// [width]×[height] 的 PNG。
Future<Uint8List> png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), Paint()..color = const Color(0xFF336699));
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TestServices services;
  setUp(() async {
    services = await TestServices.create();
    await services.addSources([{'bookSourceUrl': 'https://s.com', 'bookSourceName': '书源'}]);
  });
  tearDown(() => services.db.close());

  ContentImages images({int budget = 50 << 20}) => ContentImages(
    db: services.db,
    source: services.contentSource,
    book: book('b'),
    devicePixelRatio: 2,
    budget: budget,
  );

  test('读缓存或下载并写入缓存，量出原始尺寸；下载失败、不是图片的不在结果里，也不写缓存', () async {
    final bytes = await png(30, 20);
    await services.db.putContentImage('b', 'cached.png', await png(100, 50));
    services.engine.onImage = (source, book, src) async => switch (src) {
      'new.png' => bytes,
      'text.png' => Uint8List.fromList('not an image'.codeUnits),
      _ => throw Exception('404'),
    };
    final store = images();
    final sizes = await store.prepare(['cached.png', 'new.png', 'text.png', 'missing.png', 'new.png']);
    expect(sizes, {'cached.png': const Size(100, 50), 'new.png': const Size(30, 20)});
    expect(services.engine.calls.where((c) => c.startsWith('image')).toList()..sort(), ['image missing.png', 'image new.png', 'image text.png']);
    expect(await services.db.getContentImage('b', 'new.png'), bytes);
    expect(await services.db.getContentImage('b', 'text.png'), isNull);
    expect(await services.db.getContentImage('b', 'missing.png'), isNull);
    store.dispose();
  });

  test('同时最多下载 4 张', () async {
    final bytes = await png(10, 10);
    var running = 0, peak = 0;
    final release = Completer<void>();
    services.engine.onImage = (source, book, src) async {
      peak = (++running) > peak ? running : peak;
      await release.future;
      running--;
      return bytes;
    };
    final store = images();
    final done = store.prepare([for (var i = 0; i < 9; i++) '$i.png']);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(peak, ContentImages.concurrency);
    release.complete();
    expect(await done, hasLength(9));
    store.dispose();
  });

  test('按显示尺寸乘像素密度解码，解码好后通知；超出上限时先释放最久没用的', () async {
    for (final name in ['a', 'b', 'c']) {
      await services.db.putContentImage('b', '$name.png', await png(400, 200));
    }
    // 每张解码成 200×100（显示宽 100 × 密度 2），80000 字节；上限放得下两张
    final store = images(budget: 170000);
    var notified = 0;
    store.addListener(() => notified++);
    Future<ui.Image> decoded(String src) async {
      for (var i = 0; i < 100; i++) {
        if (store.bitmap(src, const Size(100, 50)) case final image?) return image;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      fail('$src 没有解码出来');
    }

    expect(store.bitmap('a.png', const Size(100, 50)), isNull);
    final a = await decoded('a.png');
    expect((a.width, a.height), (200, 100));
    await decoded('b.png');
    await decoded('a.png'); // a 变成最近用过的
    await decoded('c.png');
    expect(notified, 3);
    expect(store.bitmap('a.png', const Size(100, 50)), isNotNull);
    expect(store.bitmap('b.png', const Size(100, 50)), isNull, reason: 'b 最久没用，被释放');
    store.dispose();
  });

  test('看大图按原始分辨率解码；不在缓存里的抛出错误', () async {
    await services.db.putContentImage('b', 'a.png', await png(400, 200));
    final store = images();
    final image = await store.full('a.png');
    expect((image.width, image.height), (400, 200));
    image.dispose();
    await expectLater(store.full('none.png'), throwsStateError);
    store.dispose();
  });
}
