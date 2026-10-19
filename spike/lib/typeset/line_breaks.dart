/// 1.3 断行检查：真实网文加合成的压力文本，在几种宽度下逐行检查标点避头尾。
library;

import 'two_pass.dart';

/// 规格「正文排版」：这些字不出现在行首。
const forbiddenAtStart = '，。、；：？！…”’）》」』】';

/// 规格「正文排版」：这些字不出现在行尾。
const forbiddenAtEnd = '“‘（《「『【';

/// 断行检查用的五种正文宽度：都不是字宽 18 的整数倍，避免每行都正好排满。
const checkWidths = [280.0, 320.5, 335.0, 353.0, 372.0];

/// 一章：章节名和段落。
typedef CorpusChapter = ({String title, List<String> paragraphs});

/// 解析 assets/corpus.txt：每章以「=== 章节名」开头，之后一行一段，去掉首尾空白（含全角空格）。
List<CorpusChapter> parseCorpus(String source) {
  final chapters = <CorpusChapter>[];
  for (final line in source.split('\n')) {
    if (line.startsWith('=== ')) {
      chapters.add((title: line.substring(4), paragraphs: []));
    } else if (line.trim() case final text when text.isNotEmpty && chapters.isNotEmpty) {
      chapters.last.paragraphs.add(text);
    }
  }
  return chapters;
}

/// 真实网文里很少出现的标点，用合成的段落补上：每个字放在离段首不同距离的位置，
/// 加上五种宽度，基本能让每个字都碰到一次行首或行尾。
List<String> stressParagraphs() {
  const filler = '甲乙丙丁戊己庚辛壬癸子丑寅卯辰巳午未申酉';
  String run(int n) => List.generate(n, (i) => filler[i % filler.length]).join();
  return [
    for (final c in forbiddenAtStart.split('')) [for (var k = 1; k <= 30; k++) '${run(k % 11 + 1)}$c'].join(),
    for (final c in forbiddenAtEnd.split('')) [for (var k = 1; k <= 30; k++) '${run(k % 11 + 1)}$c${run(2)}'].join(),
    [for (var k = 1; k <= 30; k++) '${run(k % 13 + 1)}……'].join(),
    [for (var k = 1; k <= 30; k++) '${run(k % 13 + 1)}——${run(2)}'].join(),
    [for (var k = 1; k <= 20; k++) '${run(k % 9 + 1)}：“${run(k % 5 + 1)}，‘${run(3)}’。”'].join(),
    [for (var k = 1; k <= 20; k++) '${run(k % 9 + 1)}《${run(4)}》「${run(2)}」『${run(2)}』【${run(2)}】（${run(3)}）'].join(),
    [for (var k = 1; k <= 12; k++) '${run(k % 7 + 1)}iPhone 15 Pro Max，说：“OK，我们 go！”然后用 GitHub 下载了 v1.$k.zip；'].join(),
  ];
}

/// 一处违规：[kind] 是「行首」「行尾」「拆开」「区间」之一，[context] 是断行处前后几个字（`|` 表示断行处）。
typedef Violation = ({String kind, String char, String context, double width});

/// 用 D4 的两次排版排出每一行，检查每个软换行处：
/// - 下一行的第一个字不在 [forbiddenAtStart] 里；
/// - 上一行的最后一个字不在 [forbiddenAtEnd] 里；
/// - `……`、`——` 和代理对不被拆开；
/// - 各行的字符区间首尾相接，正好覆盖整段。
List<Violation> checkLineBreaks(Iterable<String> paragraphs, TypesetStyle style, double width) {
  final violations = <Violation>[];
  for (final text in paragraphs) {
    final paragraph = TwoPassParagraph(text, style, width);
    final lines = paragraph.lines;
    void add(String kind, String char, int at) => violations.add((
      kind: kind,
      char: char,
      context: '${text.substring((at - 6).clamp(0, at), at)}|${text.substring(at, (at + 6).clamp(at, text.length))}',
      width: width,
    ));
    if (lines.first.start != 0 || lines.last.end != text.length) add('区间', '', 0);
    for (var i = 1; i < lines.length; i++) {
      final at = lines[i].start;
      if (lines[i - 1].end != at) add('区间', '', at);
      final before = text.substring(0, at).trimRight();
      final next = text[at];
      final previous = before.isEmpty ? '' : before[before.length - 1];
      if (forbiddenAtStart.contains(next)) add('行首', next, at);
      if (previous.isNotEmpty && forbiddenAtEnd.contains(previous)) add('行尾', previous, at);
      if (previous == next && (next == '…' || next == '—')) add('拆开', next, at);
      if (next.codeUnitAt(0) & 0xFC00 == 0xDC00) add('拆开', '代理对', at);
    }
    paragraph.dispose();
  }
  return violations;
}
