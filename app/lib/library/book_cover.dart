import 'package:flutter/material.dart';

import '../ui/tokens.dart';

/// 书的封面，宽高比 3:4，小圆角。没有封面或加载失败时显示浅灰底的占位封面，上面写 [title]（宫格里的封面够大，写得下书名）。
class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.url, required this.width, this.title});

  final String? url;
  final double width;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final title = this.title;
    final placeholder = ColoredBox(
      color: colors.fill,
      child: title == null
          ? null
          : Padding(
              padding: const EdgeInsets.all(8),
              child: Center(
                child: Text(
                  title,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                ),
              ),
            ),
    );
    final url = this.url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: width,
        height: width * 4 / 3,
        child: url == null || url.isEmpty
            ? placeholder
            : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder),
      ),
    );
  }
}
