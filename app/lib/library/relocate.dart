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

/// 换书源后当前章节在新目录里的序号（bookshelf「换书源后定位当前章节」，add-shelf-change-source 设计 D3）：
/// 地址和序号只在原书源里有意义，跨书源仍然成立的是章节名，其次是章节编号。
/// [matched] 为假表示没对上，序号是原序号截到新目录范围内，章内位置应当归零。
/// [chapters] 不为空：目录为空时目录链路已经以错误结束。
({int index, bool matched}) alignChapter(List<TocChapter> chapters, {required int index, required String title}) {
  final old = parseChapterTitle(title);
  final titles = [for (final chapter in chapters) chapter.isVolume ? null : parseChapterTitle(chapter.title)];

  /// 满足 [test] 的章节里序号离 [index] 最近的，距离相同时取序号小的。
  int? nearest(bool Function(ChapterTitle) test) {
    int? found;
    for (final (i, parsed) in titles.indexed) {
      if (parsed == null || !test(parsed)) continue;
      if (found == null || (i - index).abs() < (found - index).abs()) found = i;
    }
    return found;
  }

  final found =
      (old.name.isEmpty
          ? null
          : nearest((t) => t.name == old.name && (old.number == null || t.number == null || t.number == old.number))) ??
      (old.number == null ? null : nearest((t) => t.number == old.number));
  return found == null ? (index: index.clamp(0, chapters.length - 1), matched: false) : (index: found, matched: true);
}

/// 章节名里的章节编号和纯章节名（去掉编号那一段，再去掉空白和标点符号）。
typedef ChapterTitle = ({int? number, String name});

ChapterTitle parseChapterTitle(String title) {
  final match = _numbered.firstMatch(title) ?? _leadingDigits.firstMatch(title);
  final rest = match == null ? title : title.replaceRange(match.start, match.end, '');
  return (number: match == null ? null : _number(match[1]!), name: rest.replaceAll(_noise, ''));
}

final _numbered = RegExp(r'第\s*([0-9０-９]+|[零〇一二两三四五六七八九十百千万]+)\s*[章节回]');
final _leadingDigits = RegExp(r'^\s*([0-9０-９]+)');
final _noise = RegExp(r'[\p{P}\p{S}\s]', unicode: true);

const _digits = {'零': 0, '〇': 0, '一': 1, '二': 2, '两': 2, '三': 3, '四': 4, '五': 5, '六': 6, '七': 7, '八': 8, '九': 9};
const _units = {'十': 10, '百': 100, '千': 1000};

/// 阿拉伯数字（全角转半角）或中文数字。中文数字按「个十百千」进位，「万」把前面的数乘一万；
/// 开头的「十」是一十（「十二」是 12）。
int _number(String text) {
  final first = text.codeUnitAt(0);
  if (first < 0x80 || (first >= 0xFF10 && first <= 0xFF19)) {
    return int.parse(String.fromCharCodes(text.codeUnits.map((c) => c >= 0xFF10 ? c - 0xFF10 + 0x30 : c)));
  }
  var (total, section, digit) = (0, 0, 0);
  for (final char in text.split('')) {
    if (_digits[char] case final value?) {
      digit = value;
    } else if (_units[char] case final unit?) {
      section += (digit == 0 ? 1 : digit) * unit;
      digit = 0;
    } else {
      // 万
      total += (section + digit) * 10000;
      section = digit = 0;
    }
  }
  return total + section + digit;
}
