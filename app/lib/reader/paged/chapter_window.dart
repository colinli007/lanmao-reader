import 'package:flutter/foundation.dart';

import '../../library/content_source.dart';
import '../../storage/database.dart';
import '../chapter_format.dart';
import '../content_images.dart';
import '../layout/chapter_layout.dart';

/// 取第 index 章排版前的正文（读缓存或执行正文链路）。失败时抛出 [ContentLoadException]。
typedef ChapterLoader = Future<FormattedChapter> Function(int index);

/// 窗口里一章的状态（设计 D9）。
sealed class SlotState {
  const SlotState();
}

final class SlotLoading extends SlotState {
  const SlotLoading();
}

final class SlotFailed extends SlotState {
  const SlotFailed(this.message);

  final String message;
}

final class SlotReady extends SlotState {
  const SlotReady(this.layout);

  final ChapterLayout layout;
}

/// 分页视图里的一页：正文的某一页，或者一个还不能显示的章节（加载中、失败）。
sealed class WindowPage {
  const WindowPage(this.chapter);

  final int chapter;
}

/// 第 [chapter] 章的第 [page] 页。
final class TextPage extends WindowPage {
  const TextPage(super.chapter, this.page);

  final int page;

  @override
  bool operator ==(Object other) => other is TextPage && other.chapter == chapter && other.page == page;

  @override
  int get hashCode => Object.hash(chapter, page);

  @override
  String toString() => 'TextPage($chapter, $page)';
}

/// 第 [chapter] 章还没有可显示的内容：加载中、加载失败，或者往前翻时上一章还没排完。
/// 有了以后换成包含偏移 [offset] 的页；[offset] 为空时换成这一章的最后一页（reader「章节之间连续翻页」）。
final class PendingPage extends WindowPage {
  const PendingPage(super.chapter, {this.offset});

  final int? offset;

  @override
  bool operator ==(Object other) => other is PendingPage && other.chapter == chapter && other.offset == offset;

  @override
  int get hashCode => Object.hash(chapter, offset);

  @override
  String toString() => 'PendingPage($chapter, offset: $offset)';
}

/// 往前或往后翻一页的结果。
sealed class Turn {
  const Turn();
}

/// 翻到 [page]。
final class TurnTo extends Turn {
  const TurnTo(this.page);

  final WindowPage page;
}

/// 已到头：第一章第一页往前（[first]），或最后一章最后一页往后。
final class TurnAtEdge extends Turn {
  const TurnAtEdge({required this.first});

  final bool first;
}

/// 当前是加载中的页，不翻。
final class TurnBlocked extends Turn {
  const TurnBlocked();
}

final class _Slot {
  SlotState state = const SlotLoading();
}

/// 三章窗口（设计 D9）：当前章和它前后各一个不是卷的章节。
///
/// 窗口自己加载正文（[load]）并排版；当前章同步排到当前页再多一页，其余部分和相邻章分帧排完（设计 D6）。
/// 翻进相邻章时窗口整体移一格，离开窗口的章释放排版结果（设计 D7）。
class ChapterWindow extends ChangeNotifier {
  ChapterWindow({required this.chapters, required this.load, required LayoutSpec spec, this.images, this.schedule = scheduleNextFrame})
    : _spec = spec;

  final List<TocChapter> chapters;
  final ChapterLoader load;

  /// 这本书的正文图片：排版时画图，长按时看大图（add-content-images 设计 D4、D8）。
  final ContentImages? images;
  final LayoutScheduler schedule;

  LayoutSpec _spec;
  LayoutSpec get spec => _spec;

  final Map<int, _Slot> _slots = {};
  WindowPage _current = const PendingPage(0, offset: 0);
  bool _disposed = false;

  WindowPage get current => _current;

  int get chapter => _current.chapter;

  /// 第 [index] 章在窗口里的状态；不在窗口里时为空。
  SlotState? slotOf(int index) => _slots[index]?.state;

  ChapterLayout? layoutOf(int index) => switch (_slots[index]?.state) {
    SlotReady(:final layout) => layout,
    _ => null,
  };

  /// 读到的位置（设计 D13）：有锚点时是锚点（滚动模式屏幕顶部那一行的首字、改设置前的位置），
  /// 否则是当前页首字的偏移。加载中的页是要去的偏移；要去上一章的末页时还不知道，记为章首。
  int get offset =>
      _anchor ??
      switch (_current) {
        TextPage(:final chapter, :final page) => layoutOf(chapter)!.pages[page].start,
        PendingPage(:final offset) => offset ?? 0,
      };

  /// 见 [anchorAt]、[open]。翻页时清掉；重排时保留，这样字号改大再改回来，还是原来那一页。
  int? _anchor;

  /// 上一个、下一个不是卷的章节。
  int? neighbor(int index, int step) {
    for (var i = index + step; i >= 0 && i < chapters.length; i += step) {
      if (!chapters[i].isVolume) return i;
    }
    return null;
  }

  /// 打开第 [index] 章，停在包含 [offset] 的页（菜单换章、目录跳转、打开书）。[offset] 记为锚点：
  /// 它是确切的阅读位置（保存的进度），切到滚动模式时要回到这一行，而不是这一页的页首。
  void open(int index, {int offset = 0}) {
    _anchor = offset;
    _current = PendingPage(index, offset: offset);
    _recenter(index);
    _resolve();
    notifyListeners();
  }

  /// 往后翻一页的目标（不改变当前页，确定翻页后再 [moveTo]）。
  Turn pageAfter() => switch (_current) {
    PendingPage() => const TurnBlocked(),
    TextPage(:final chapter, :final page) when page + 1 < layoutOf(chapter)!.pages.length => TurnTo(TextPage(chapter, page + 1)),
    TextPage(:final chapter) => switch (neighbor(chapter, 1)) {
      null => const TurnAtEdge(first: false),
      final next => TurnTo(_entry(next, 0)),
    },
  };

  /// 往前翻一页的目标。
  Turn pageBefore() => switch (_current) {
    PendingPage() => const TurnBlocked(),
    TextPage(:final chapter, :final page) when page > 0 => TurnTo(TextPage(chapter, page - 1)),
    TextPage(:final chapter) => switch (neighbor(chapter, -1)) {
      null => const TurnAtEdge(first: true),
      final previous => TurnTo(_entry(previous, null)),
    },
  };

  /// 进入第 [index] 章停在 [offset]（为空时是最后一页）的那一页：能显示就是正文页，否则是加载中的页。
  WindowPage _entry(int index, int? offset) {
    final layout = layoutOf(index);
    if (layout == null || (offset == null && !layout.complete)) return PendingPage(index, offset: offset);
    if (offset == null) return TextPage(index, layout.pages.length - 1);
    layout.layoutThrough(offset);
    return TextPage(index, layout.pageAt(offset));
  }

  /// 翻到 [page]（[pageAfter]、[pageBefore] 给出的目标）。翻进相邻章时窗口移一格。
  void moveTo(WindowPage page) {
    _anchor = null;
    final changed = page.chapter != _current.chapter;
    _current = page;
    if (changed) _recenter(page.chapter);
    // 预加载失败时不提示；翻进这一章时重新加载（reader「预加载相邻章节」）
    if (page is PendingPage && _slots[page.chapter]?.state is SlotFailed) _load(page.chapter);
    _resolve();
    notifyListeners();
  }

  /// 滚动模式停下时，把读到的位置定在本章偏移 [offset]（屏幕顶部那一行的首字，设计 D12）：当前页换成包含它的页。
  void anchorAt(int offset) {
    final layout = layoutOf(_current.chapter);
    if (layout == null || offset == this.offset) return;
    layout.layoutThrough(offset);
    _current = TextPage(_current.chapter, layout.pageAt(offset));
    _anchor = offset;
    _resolve();
    notifyListeners();
  }

  /// 失败页上的重试。
  void retry(int index) {
    if (_slots[index]?.state is! SlotFailed) return;
    _load(index);
    notifyListeners();
  }

  /// 字号、行距或正文区域变了：三章全部重排，当前章同步排到原来那页的首字（设计 D6、D14）。
  ///
  /// 不通知监听者：阅读页在布局阶段（LayoutBuilder 里）按新的尺寸调用它，接着就用新的结果构建分页视图；
  /// 这时通知会让上层在构建期间 setState。页序号变了，章节和偏移都没变，不需要别人知道。
  void resize(LayoutSpec spec) {
    if (spec == _spec) return;
    // 先换成加载中的页：重排当前章时同步排到这个偏移。之后锚点留在原来那个字上
    final current = _current;
    final last = current is PendingPage && current.offset == null;
    _current = PendingPage(current.chapter, offset: last ? null : offset);
    if (!last) _anchor = offset;
    _spec = spec;
    for (final MapEntry(key: index, value: slot) in _slots.entries) {
      if (slot.state case SlotReady(:final layout)) {
        layout.dispose();
        slot.state = SlotReady(_layout(index, layout.chapter));
      }
    }
    _resolve();
  }

  /// 窗口移到第 [index] 章：留下它和前后各一个不是卷的章节，其余释放，缺的开始加载。
  /// 先请求用户在等的当前章，再请求更可能翻到的下一章，最后是上一章。
  void _recenter(int index) {
    final keep = {index, neighbor(index, 1), neighbor(index, -1)}.whereType<int>().toSet();
    _slots.removeWhere((key, slot) {
      if (keep.contains(key)) return false;
      if (slot.state case SlotReady(:final layout)) layout.dispose();
      return true;
    });
    for (final key in keep) {
      if (!_slots.containsKey(key)) _load(key);
    }
  }

  void _load(int index) {
    final slot = _slots[index] = _Slot();
    final chapter = chapters[index];
    if (chapter.isVolume) {
      slot.state = SlotReady(_layout(index, (title: chapter.title, paragraphs: const [])));
      return;
    }
    load(index).then(
      (content) => _settle(index, slot, () => SlotReady(_layout(index, content))),
      onError: (Object e) => _settle(index, slot, () => SlotFailed(e is ContentLoadException ? e.message : '$e')),
    );
  }

  /// 加载结束：这一章已经离开窗口或者重新加载了（槽位换了）时丢弃结果。
  void _settle(int index, _Slot slot, SlotState Function() state) {
    if (_disposed || !identical(_slots[index], slot)) return;
    slot.state = state();
    _resolve();
    notifyListeners();
  }

  /// 排一章：当前章同步排到要显示的页，其余部分分帧排；排出新的页时看看加载中的页能不能换成正文页。
  ChapterLayout _layout(int index, FormattedChapter content) {
    final layout = ChapterLayout(content, _spec, isVolume: chapters[index].isVolume, images: images);
    final current = _current;
    layout.layoutThrough(current is PendingPage && current.chapter == index ? current.offset ?? 0 : 0);
    layout.addListener(() {
      if (_current case PendingPage(:final chapter) when chapter == index && _resolve()) notifyListeners();
    });
    layout.layoutInBackground(schedule);
    return layout;
  }

  /// 当前是加载中的页、目标章已经可以显示时，换成目标页。返回是否换了。
  bool _resolve() {
    if (_current case PendingPage(:final chapter, :final offset)) {
      final page = _entry(chapter, offset);
      if (page is! TextPage) return false;
      _current = page;
    }
    final page = _current as TextPage;
    final layout = layoutOf(page.chapter)!;
    layout.layoutThrough(layout.pages[page.page].start);
    layout.retainAround(page.page);
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    for (final slot in _slots.values) {
      if (slot.state case SlotReady(:final layout)) layout.dispose();
    }
    _slots.clear();
    super.dispose();
  }
}
