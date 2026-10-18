import 'package:flutter/material.dart';

/// 封面：取不到时显示占位。
class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.url, required this.width});

  final String? url;
  final double width;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.menu_book_outlined),
    );
    final url = this.url;
    return SizedBox(
      width: width,
      height: width * 4 / 3,
      child: url == null || url.isEmpty
          ? placeholder
          : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder),
    );
  }
}
