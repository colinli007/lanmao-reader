import 'package:flutter/material.dart';

import '../ui/cinema.dart';

/// 封面：宽高比和设计稿一致（136×196 等，约 1:1.44）。取不到时显示书名占位。
class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.url, required this.width, this.height, this.title, this.radius = 0});

  /// 宽高比：设计稿里的封面都是这个比例。
  static const aspectRatio = 1 / 1.44;

  final String? url;
  final double width;

  /// 为空时按 [aspectRatio]。
  final double? height;

  /// 占位上显示的书名。
  final String? title;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final placeholder = _Placeholder(title: title, width: width);
    final url = this.url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height ?? width / aspectRatio,
        child: url == null || url.isEmpty ? placeholder : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.title, required this.width});

  final String? title;
  final double width;

  @override
  Widget build(BuildContext context) {
    final title = this.title;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Night.elevated, Night.surface]),
      ),
      child: Center(
        child: title == null || width < 56
            ? Icon(Icons.menu_book_outlined, color: Night.text3, size: width * 0.4)
            : Padding(
                padding: EdgeInsets.all(width * 0.12),
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: serif(width * 0.14, color: Night.text2, height: 1.3),
                ),
              ),
      ),
    );
  }
}
