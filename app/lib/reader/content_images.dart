import 'dart:async';
import 'dart:collection';
import 'dart:developer';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../library/content_source.dart';
import '../storage/database.dart';
import 'layout/chapter_layout.dart';

/// 一本书的正文图片（reader「正文图片」）：一个阅读页一个，离开阅读页时释放。
///
/// - 排版前：[prepare] 取到一章的图片并量出原始尺寸（add-content-images 设计 D1）。
/// - 画的时候：[bitmap] 按显示尺寸解码，放进按字节数计的 LRU，解码完成后通知重画（设计 D4）。
/// - 看大图：[full] 按原始分辨率解码，不进 LRU（设计 D8）。
final class ContentImages extends ChangeNotifier implements ImageBitmaps {
  ContentImages({
    required AppDatabase db,
    required BookContentSource source,
    required this.book,
    required this.devicePixelRatio,
    this.budget = 50 << 20,
  }) : _db = db,
       _source = source;

  final AppDatabase _db;
  final BookContentSource _source;
  final ShelfBook book;

  /// 显示尺寸乘以它是解码的像素宽度。
  final double devicePixelRatio;

  /// 解码好的位图最多占的字节数，和 Legado 默认的 50MB 相同。
  final int budget;

  /// 同一章的图片同时最多下载几张。
  static const concurrency = 4;

  /// 下载中的图片，按地址：同一张图同时只下载一次。
  final Map<String, Future<Size>> _loading = {};

  /// 解码好的位图，按（地址，像素宽度），最近用过的在后面。
  final LinkedHashMap<(String, int), ui.Image> _bitmaps = LinkedHashMap();
  final Set<(String, int)> _decoding = {};

  /// 解码失败的图片：不再反复尝试，一直画占位框。
  final Set<(String, int)> _broken = {};
  int _bytes = 0;
  bool _disposed = false;

  // ---------------------------------------------------------------- 排版前

  /// 取到 [srcs] 的字节并量出原始尺寸（设计 D1）：先读缓存，没有时下载，是图片才写入缓存。失败的不在结果里。
  Future<Map<String, Size>> prepare(Iterable<String> srcs) async {
    final queue = Queue.of(srcs.toSet());
    final sizes = <String, Size>{};
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final src = queue.removeFirst();
        try {
          // whenComplete 会等回调返回的 Future：回调不能返回 _loading.remove 的结果（就是这个 Future 自己）
          sizes[src] = await (_loading[src] ??= _load(src).whenComplete(() {
            _loading.remove(src);
          }));
        } catch (e) {
          log('正文图片加载失败：$src', error: e, name: 'reader');
        }
      }
    }

    final workers = math.min(concurrency, queue.length);
    await Future.wait([for (var i = 0; i < workers; i++) worker()]);
    return sizes;
  }

  Future<Size> _load(String src) async {
    final cached = await _db.getContentImage(book.bookUrl, src);
    if (cached != null) return sizeOf(cached);
    final bytes = await _source.loadImage(book, src);
    final size = await sizeOf(bytes);
    await _db.putContentImage(book.bookUrl, src, bytes);
    return size;
  }

  /// 图片的原始尺寸：只读图片头，不解码整张图；不是图片时抛出错误。
  static Future<Size> sizeOf(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final size = Size(descriptor.width.toDouble(), descriptor.height.toDouble());
      descriptor.dispose();
      return size;
    } finally {
      buffer.dispose();
    }
  }

  // ---------------------------------------------------------------- 画

  @override
  ui.Image? bitmap(String src, Size size) {
    final key = (src, math.max(1, (size.width * devicePixelRatio).round()));
    final image = _bitmaps.remove(key);
    if (image != null) return _bitmaps[key] = image;
    if (!_broken.contains(key) && _decoding.add(key)) unawaited(_decode(key));
    return null;
  }

  Future<void> _decode((String, int) key) async {
    try {
      final image = await _decodeAt(key.$1, key.$2);
      if (_disposed) return image.dispose();
      _bitmaps[key] = image;
      _bytes += _sizeInBytes(image);
      _evict();
      notifyListeners();
    } catch (e) {
      _broken.add(key);
      log('正文图片解码失败：${key.$1}', error: e, name: 'reader');
    } finally {
      _decoding.remove(key);
    }
  }

  /// 超出 [budget] 时从最久没用过的开始释放，至少留下刚放进去的那张。
  void _evict() {
    while (_bytes > budget && _bitmaps.length > 1) {
      final oldest = _bitmaps.keys.first;
      final image = _bitmaps.remove(oldest)!;
      _bytes -= _sizeInBytes(image);
      image.dispose();
    }
  }

  static int _sizeInBytes(ui.Image image) => image.width * image.height * 4;

  // ---------------------------------------------------------------- 看大图

  /// 按原始分辨率解码，调用方负责 dispose。
  Future<ui.Image> full(String src) => _decodeAt(src, null);

  /// [width] 为 null 时按原始宽度；比原始宽度大时不放大。
  Future<ui.Image> _decodeAt(String src, int? width) async {
    final bytes = await _db.getContentImage(book.bookUrl, src);
    if (bytes == null) throw StateError('图片不在缓存里');
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      final codec = await descriptor.instantiateCodec(targetWidth: width == null ? null : math.min(width, descriptor.width));
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } finally {
      descriptor.dispose();
      buffer.dispose();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final image in _bitmaps.values) {
      image.dispose();
    }
    _bitmaps.clear();
    super.dispose();
  }
}
