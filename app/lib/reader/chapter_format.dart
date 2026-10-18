/// 排版后的一段正文。[offset] 是这一段在排版后正文（各段以换行连接）里的起始字符偏移，阅读进度存的就是它（设计 D8）。
typedef Paragraph = ({String text, int offset});

typedef FormattedChapter = ({String title, List<Paragraph> paragraphs});

const _indent = '　　';
final _image = RegExp(r'<img\b[^>]*>', caseSensitive: false);
final _lineBreak = RegExp(r'\r\n|\r|\n');

/// reader「正文排版」：按换行切段，去掉每段首尾的空白（含全角空格），丢弃空段，段首缩进两个全角空格；
/// 第一段与章节名相同时去掉；`<img>` 本次不显示，换成「[图片]」。
FormattedChapter formatChapter(String title, String content) {
  final lines = [
    for (final line in content.replaceAll(_image, '[图片]').split(_lineBreak))
      if (line.trim() case final text when text.isNotEmpty) text,
  ];
  if (lines.isNotEmpty && lines.first == title.trim()) lines.removeAt(0);
  var offset = 0;
  final paragraphs = <Paragraph>[];
  for (final line in lines) {
    final text = '$_indent$line';
    paragraphs.add((text: text, offset: offset));
    offset += text.length + 1;
  }
  return (title: title, paragraphs: paragraphs);
}

/// 包含 [position] 的段落下标：最后一个起始偏移不大于它的段落。
int paragraphAt(List<Paragraph> paragraphs, int position) {
  var index = 0;
  for (final (i, paragraph) in paragraphs.indexed) {
    if (paragraph.offset > position) break;
    index = i;
  }
  return index;
}
