import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'content_images.dart';

/// 看大图（reader「看大图」，add-content-images 设计 D8）：黑底，按原始分辨率显示，双指缩放和拖动，点一下关闭。
class ImageViewerPage extends StatefulWidget {
  const ImageViewerPage({super.key, required this.src, required this.images});

  final String src;
  final ContentImages images;

  /// 从阅读页打开：淡入淡出，没有页面滑动。
  static Future<void> open(BuildContext context, String src, ContentImages images) => Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: true,
      pageBuilder: (_, _, _) => ImageViewerPage(src: src, images: images),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
    ),
  );

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  ui.Image? _image;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    widget.images.full(widget.src).then(
      (image) => mounted ? setState(() => _image = image) : image.dispose(),
      onError: (Object _) => mounted ? setState(() => _failed = true) : null,
    );
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(),
        child: Semantics(
          label: '大图，点一下关闭',
          child: Center(
            child: image != null
                ? InteractiveViewer(maxScale: 5, child: RawImage(image: image))
                : _failed
                ? const Text('图片打不开', style: TextStyle(color: Colors.white70))
                : const CircularProgressIndicator(color: Colors.white70),
          ),
        ),
      ),
    );
  }
}
