import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../storage/database.dart';
import 'content_source.dart';

/// 取到正文里的一张图片并量出原始尺寸（reader「正文图片」，add-content-images 设计 D1）：先读缓存，没有时下载，
/// 是图片才写入缓存。阅读页和缓存全本都用它，缓存的结果一样（add-book-cache 设计 D3）。失败时抛出错误。
Future<Size> cacheContentImage(AppDatabase db, BookContentSource source, ShelfBook book, String src) async {
  final cached = await db.getContentImage(book.bookUrl, src);
  if (cached != null) return imageSizeOf(cached);
  final bytes = await source.loadImage(book, src);
  final size = await imageSizeOf(bytes);
  // 下载期间可能换源或移出书架；和删除事务串行，不能把旧书的图片缓存写回来。
  await db.transaction(() async {
    if (await db.getBook(book.bookUrl) != null) await db.putContentImage(book.bookUrl, src, bytes);
  });
  return size;
}

/// 图片的原始尺寸：只读图片头，不解码整张图；不是图片时抛出错误。
Future<Size> imageSizeOf(Uint8List bytes) async {
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
