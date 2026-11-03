import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanmao_reader/library/content_source.dart';
import 'package:lanmao_reader/reader/chapter_format.dart';
import 'package:lanmao_reader/reader/layout/chapter_layout.dart';
import 'package:lanmao_reader/reader/paged/chapter_window.dart';

import '../../support/fixtures.dart';

const _spec = LayoutSpec(fontSize: 18, lineHeight: 1.8, size: Size(335, 600));

/// 第 5 章是卷，其余每章 30 段，排出来有好几页。
final _chapters = [for (var i = 0; i < 8; i++) chapter('b', i, volume: i == 5)];

FormattedChapter _content(int index) =>
    formatChapter('第$index章', [for (var p = 0; p < 30; p++) '第$index章第$p段，山风从谷底卷上来，吹得崖边的松枝簌簌作响。'].join('\n'));

/// 假的加载器：默认立即返回正文；[hold] 里的章节等测试手动完成；[fail] 里的章节失败一次。
final class _Loader {
  final Map<int, Completer<FormattedChapter>> hold = {};
  final Set<int> fail = {};
  final List<int> calls = [];

  Future<FormattedChapter> call(int index) async {
    calls.add(index);
    if (fail.remove(index)) throw const ContentLoadException('网络错误');
    if (hold[index] case final completer?) return completer.future;
    return _content(index);
  }
}

/// 手动执行的分帧调度器。
final class _Scheduler {
  final List<VoidCallback> tasks = [];

  void call(VoidCallback task) => tasks.add(task);

  void drain() {
    while (tasks.isNotEmpty) {
      tasks.removeAt(0)();
    }
  }
}

void main() {
  late _Loader loader;
  late _Scheduler scheduler;
  late ChapterWindow window;

  setUp(() {
    loader = _Loader();
    scheduler = _Scheduler();
    window = ChapterWindow(chapters: _chapters, load: loader.call, spec: _spec, schedule: scheduler.call);
  });

  tearDown(() => window.dispose());

  /// 打开第 [index] 章，等正文返回并且全部排完。
  Future<void> openAndSettle(int index, {int offset = 0}) async {
    window.open(index, offset: offset);
    await pumpEventQueue();
    scheduler.drain();
  }

  int lastPage(int index) => window.layoutOf(index)!.pages.length - 1;

  WindowPage turned(Turn turn) => (turn as TurnTo).page;

  group('章节之间连续翻页', () {
    test('翻进下一章：本章最后一页往后翻，是下一章第 1 页，当前章节变成下一章', () async {
      await openAndSettle(3);
      window.moveTo(TextPage(3, lastPage(3)));
      final next = turned(window.pageAfter());
      expect(next, const TextPage(4, 0));
      window.moveTo(next);
      expect(window.chapter, 4);
    });

    test('往回翻到上一章的末页', () async {
      await openAndSettle(4);
      expect(window.current, const TextPage(4, 0));
      expect(turned(window.pageBefore()), TextPage(3, lastPage(3)));
    });

    test('下一章还没加载好：先是加载中的页，正文返回后换成下一章第 1 页', () async {
      loader.hold[4] = Completer();
      await openAndSettle(3);
      window.moveTo(TextPage(3, lastPage(3)));
      final next = turned(window.pageAfter());
      expect(next, const PendingPage(4, offset: 0));
      window.moveTo(next);
      expect(window.slotOf(4), isA<SlotLoading>());
      var notified = false;
      window.addListener(() => notified = true);
      loader.hold[4]!.complete(_content(4));
      await pumpEventQueue();
      expect(window.current, const TextPage(4, 0));
      expect(notified, isTrue);
    });

    test('已是最后一章、已是第一章：不翻页', () async {
      await openAndSettle(7);
      window.moveTo(TextPage(7, lastPage(7)));
      expect(window.pageAfter(), isA<TurnAtEdge>().having((t) => t.first, 'first', false));
      await openAndSettle(0);
      expect(window.pageBefore(), isA<TurnAtEdge>().having((t) => t.first, 'first', true));
    });
  });

  test('相邻章节跳过卷：第 4 章往后是第 6 章，第 6 章往前是第 4 章', () async {
    await openAndSettle(4);
    window.moveTo(TextPage(4, lastPage(4)));
    expect(turned(window.pageAfter()), const TextPage(6, 0));
    await openAndSettle(6);
    expect(turned(window.pageBefore()), TextPage(4, lastPage(4)));
    expect(window.slotOf(5), isNull, reason: '卷不在窗口里');
  });

  test('上一章还没排完时往前翻：先是加载中的页，排完后换成上一章的末页', () async {
    window.open(4);
    await pumpEventQueue();
    // 分帧任务还没执行：上一章只排了开头
    expect(window.layoutOf(3)!.complete, isFalse);
    final previous = turned(window.pageBefore());
    expect(previous, const PendingPage(3));
    window.moveTo(previous);
    scheduler.drain();
    expect(window.current, TextPage(3, lastPage(3)));
  });

  test('窗口移动后，离开窗口的章已释放，新的相邻章开始加载', () async {
    await openAndSettle(3);
    final leaving = window.layoutOf(2)!;
    window.moveTo(TextPage(3, lastPage(3)));
    window.moveTo(turned(window.pageAfter()));
    expect(window.slotOf(2), isNull);
    expect(() => ChangeNotifier.debugAssertNotDisposed(leaving), throwsFlutterError);
    expect(loader.calls, [3, 4, 2, 6]);
  });

  test('预加载失败不影响当前章；翻进那一章时重新加载', () async {
    loader.fail.add(4);
    await openAndSettle(3);
    expect(window.slotOf(4), isA<SlotFailed>());
    window.moveTo(TextPage(3, lastPage(3)));
    window.moveTo(turned(window.pageAfter()));
    await pumpEventQueue();
    expect(window.current, const TextPage(4, 0));
    expect(loader.calls.where((i) => i == 4), hasLength(2));
  });

  test('加载失败的页：显示原因，点重试后显示', () async {
    loader.fail.add(3);
    await openAndSettle(3);
    expect(window.current, const PendingPage(3, offset: 0));
    expect((window.slotOf(3)! as SlotFailed).message, '网络错误');
    window.retry(3);
    await pumpEventQueue();
    expect(window.current, const TextPage(3, 0));
  });

  test('打开时停在包含进度偏移的页', () async {
    await openAndSettle(3);
    final page = window.layoutOf(3)!.pages[2];
    await openAndSettle(3, offset: page.start + 5);
    expect(window.current, const TextPage(3, 2));
    // 读到的位置是打开时给的那个字（锚点），翻一页以后变成页首
    expect(window.offset, page.start + 5);
    window.moveTo(turned(window.pageAfter()));
    expect(window.offset, window.layoutOf(3)!.pages[3].start);
  });

  test('改字号后重排，停在包含原来那页首字的页', () async {
    await openAndSettle(3);
    window.moveTo(const TextPage(3, 3));
    final first = window.offset;
    window.resize(const LayoutSpec(fontSize: 24, lineHeight: 1.8, size: Size(335, 600)));
    final layout = window.layoutOf(3)!;
    final page = (window.current as TextPage).page;
    expect(layout.pages[page].start, lessThanOrEqualTo(first));
    expect(page == layout.pages.length - 1 || layout.pages[page + 1].start > first, isTrue);
  });
}
