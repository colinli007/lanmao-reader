import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/book_cover.dart';
import '../ui/cinema.dart';
import 'reader_page.dart';
import 'reader_settings.dart';

/// 从书架、详情页的「继续阅读」进入正文（设计稿「过渡动效 · 分镜」，设计 D10）：
///
/// - 0–280ms：封面在中间放大，底色由夜色转成暖棕。
/// - 280–420ms：底色铺成正文的底色，正文淡入，封面淡出。
/// - 进入后菜单先显示，2 秒后自动收起（[ReaderPage.introMenu]）。
///
/// [startAt] 同 [ReaderPage.startAt]；[coverUrl]、[title] 是转场里放大的封面。
Future<void> openReader(BuildContext context, {required String bookUrl, int? startAt, String? coverUrl, String? title}) {
  final settings = ProviderScope.containerOf(context, listen: false).read(readerSettingsProvider);
  final paper = settings.effectiveTheme(MediaQuery.platformBrightnessOf(context)).background;
  final route = PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 420),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (_, _, _) => ReaderPage(bookUrl: bookUrl, startAt: startAt, introMenu: true),
    transitionsBuilder: (context, animation, _, child) => _Transition(
      animation: animation,
      paper: paper,
      cover: BookCover(url: coverUrl, title: title, width: 150, radius: 10),
      child: child,
    ),
  );
  return Navigator.of(context).push(route);
}

class _Transition extends StatelessWidget {
  const _Transition({required this.animation, required this.paper, required this.cover, required this.child});

  final Animation<double> animation;
  final Color paper;
  final Widget cover;
  final Widget child;

  /// 280ms / 420ms：封面放大、底色转暖的这一段结束的位置。
  static const _split = 2 / 3;

  static const _warm = Color(0xFF3B3128);

  @override
  Widget build(BuildContext context) {
    final background = TweenSequence([
      TweenSequenceItem(
        tween: ColorTween(begin: Night.bg, end: _warm),
        weight: _split,
      ),
      TweenSequenceItem(
        tween: ColorTween(begin: _warm, end: paper),
        weight: 1 - _split,
      ),
    ]).animate(animation);
    final grow = CurvedAnimation(
      parent: animation,
      curve: const Interval(0, _split, curve: Curves.easeOut),
    );
    final reveal = CurvedAnimation(parent: animation, curve: const Interval(_split, 1));
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => ColoredBox(
        color: background.value!,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Opacity(opacity: reveal.value, child: child),
            if (animation.value < 1)
              IgnorePointer(
                child: Center(
                  child: Opacity(
                    opacity: 1 - reveal.value,
                    child: Transform.scale(scale: 1 + 0.5 * grow.value, child: cover),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
