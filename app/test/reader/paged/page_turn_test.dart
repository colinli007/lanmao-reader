import 'package:flutter_test/flutter_test.dart';
import 'package:lanmao_reader/reader/paged/page_turn.dart';
import 'package:lanmao_reader/reader/reader_settings.dart';

void main() {
  group('松手判定', () {
    test('快速轻扫翻页：向左快速轻扫，手指只移动了一小段，完成往后翻', () {
      expect(shouldComplete(velocity: -1200, t: 0.05, forward: true), isTrue);
    });

    test('拖一点就松手：慢慢拖五分之一屏宽后停住，回到原页', () {
      expect(shouldComplete(velocity: 0, t: 0.2, forward: true), isFalse);
    });

    test('拖过去又甩回来：拖过半屏，向右快速一甩，回到原页', () {
      expect(shouldComplete(velocity: 900, t: 0.6, forward: true), isFalse);
    });

    test('往前翻：向右快速轻扫完成，向左快速一甩回到原页', () {
      expect(shouldComplete(velocity: 800, t: 0.1, forward: false), isTrue);
      expect(shouldComplete(velocity: -800, t: 0.8, forward: false), isFalse);
    });

    test('速度正好在阈值上按速度判定，差一点按距离判定', () {
      expect(shouldComplete(velocity: -300, t: 0, forward: true), isTrue);
      expect(shouldComplete(velocity: 300, t: 0.9, forward: true), isFalse);
      expect(shouldComplete(velocity: -299.9, t: 0.1, forward: true), isFalse);
      expect(shouldComplete(velocity: 299.9, t: 0.9, forward: true), isTrue);
    });

    test('t 正好是 0.35 完成，略小于 0.35 回到原页', () {
      expect(shouldComplete(velocity: 0, t: 0.35, forward: true), isTrue);
      expect(shouldComplete(velocity: 0, t: 0.3499, forward: false), isFalse);
    });
  });

  group('两页摆放', () {
    const width = 400.0;

    test('滑动：两页一起平移', () {
      expect(placePages(PageMode.slide, forward: true, t: 0.25, width: width), (current: -100.0, other: 300.0, otherOnTop: false));
      expect(placePages(PageMode.slide, forward: false, t: 0.25, width: width), (current: 100.0, other: -300.0, otherOnTop: true));
    });

    test('覆盖：往后翻时当前页移出、下一页不动；往前翻时上一页从左边盖上来', () {
      expect(placePages(PageMode.cover, forward: true, t: 0.25, width: width), (current: -100.0, other: 0.0, otherOnTop: false));
      expect(placePages(PageMode.cover, forward: false, t: 0.25, width: width), (current: 0.0, other: -300.0, otherOnTop: true));
    });

    test('t 为 1 时要翻到的页正好在原位', () {
      for (final mode in [PageMode.cover, PageMode.slide]) {
        for (final forward in [true, false]) {
          expect(placePages(mode, forward: forward, t: 1, width: width).other, 0);
        }
      }
    });
  });
}
