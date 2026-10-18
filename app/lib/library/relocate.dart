import '../storage/database.dart';

/// 目录被替换后当前章节的新序号（bookshelf「目录更新后定位当前章节」，设计 D12）：
/// 按章节地址找，地址是书内唯一的章节标识；找不到时保留原序号并截到新目录的范围内。
int relocateChapter(List<TocChapter> chapters, {required int index, required String? url}) {
  if (chapters.isEmpty) return 0;
  if (url != null) {
    final found = chapters.indexWhere((chapter) => chapter.url == url);
    if (found >= 0) return found;
  }
  return index.clamp(0, chapters.length - 1);
}
