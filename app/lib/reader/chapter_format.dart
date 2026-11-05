import 'dart:convert';
import 'dart:ui';

/// 正文里一张图片在文字里的占位：对象替换字符，在进度里算 1 个字（add-content-images 设计 D2）。
const String imageMark = '\u{FFFC}';

final int _markRune = imageMark.runes.single;

/// 图片的显示方式（reader「正文图片」）：行内，或单独成段的默认、`FULL`、`SINGLE`。
enum ImageMode { inline, normal, full, single }

/// 正文里的一张图片：[src] 是 `<img>` 的地址原文（可能带 `,{选项}`，下载和缓存都用它），[style]、[width] 是选项里的值。
/// [formatChapter] 只认出地址；[arrangeImages] 量完尺寸后换成带 [size]（原始尺寸，null 是加载失败）和 [mode] 的新对象。
final class ContentImage {
  const ContentImage._(this.src, this.style, this.width, {this.size, this.mode = ImageMode.normal});

  factory ContentImage(String src) {
    final option = _option.firstMatch(src);
    if (option != null) {
      try {
        if (jsonDecode(src.substring(option.end)) case final Map<String, Object?> json) {
          return ContentImage._(src, json['style']?.toString(), json['width']?.toString());
        }
      } on FormatException {
        // 选项不是 JSON 时当作没有选项，和下载时一样
      }
    }
    return ContentImage._(src, null, null);
  }

  static final _option = RegExp(r'\s*,\s*(?=\{)');

  final String src;
  final String? style;
  final String? width;
  final Size? size;
  final ImageMode mode;

  bool get failed => size == null;

  ContentImage _arranged(Size? size, ImageMode mode) => ContentImage._(src, style, width, size: size, mode: mode);
}

/// 排版后的一段正文。[offset] 是这一段在排版后正文里的起始字符偏移：各段以换行连接，不含缩进和章节名
/// （add-paged-reader 设计 D13）。段首缩进是排版效果，不在 [text] 里。
/// [images] 是 [text] 里每个 [imageMark] 对应的图片，按出现的顺序；单独成段的图片，[text] 只有一个 [imageMark]。
typedef Paragraph = ({String text, int offset, List<ContentImage> images});

typedef FormattedChapter = ({String title, List<Paragraph> paragraphs});

/// 单独成段的图片（不是行内图），没有时为 null。
ContentImage? blockImageOf(Paragraph paragraph) =>
    paragraph.text == imageMark && paragraph.images.length == 1 && paragraph.images.single.mode != ImageMode.inline
    ? paragraph.images.single
    : null;

/// Legado 的 `AppPattern.imgPattern`：地址里可以带 `,{选项}`，选项里有引号。
final _image = RegExp(r'''<img[^>]*src=['"]([^'"]*(?:['"][^>]+\})?)['"][^>]*>''', caseSensitive: false);
final _lineBreak = RegExp(r'\r\n|\r|\n');

/// reader「正文排版」：按换行切段，去掉每段首尾的空白（含全角空格），丢弃空段；第一段与章节名相同时去掉。
/// 每个 `<img>` 换成 [imageMark]，地址记在段落的 [Paragraph.images] 里；拆段和偏移等量完尺寸由 [arrangeImages] 完成，
/// 正文里没有图片时这里的结果就是最终结果。
FormattedChapter formatChapter(String title, String content) {
  final lines = <(String, List<ContentImage>)>[];
  for (final line in content.split(_lineBreak)) {
    final images = <ContentImage>[];
    final text = line.replaceAllMapped(_image, (match) {
      images.add(ContentImage(match[1]!));
      return imageMark;
    });
    if (text.trim() case final trimmed when trimmed.isNotEmpty) lines.add((trimmed, images));
  }
  if (lines.isNotEmpty && lines.first.$1 == title.trim()) lines.removeAt(0);
  return (title: title, paragraphs: _withOffsets(lines));
}

/// 正文里所有图片的地址，去掉重复。
Set<String> imageSourcesOf(FormattedChapter chapter) => {
  for (final paragraph in chapter.paragraphs)
    for (final image in paragraph.images) image.src,
};

/// 量完尺寸以后定下每张图的显示方式，把单独成段的图片拆成自己的段，重新算偏移（add-content-images 设计 D2、D3）。
/// [sizes] 是地址 → 原始尺寸，没有的是加载失败；[style] 是书源的 `ruleContent.imageStyle`。
FormattedChapter arrangeImages(FormattedChapter chapter, Map<String, Size> sizes, {String? style}) {
  final lines = <(String, List<ContentImage>)>[];
  for (final paragraph in chapter.paragraphs) {
    final buffer = StringBuffer();
    final inline = <ContentImage>[];
    void flush() {
      if (buffer.toString().trim() case final text when text.isNotEmpty) lines.add((text, [...inline]));
      buffer.clear();
      inline.clear();
    }

    final images = paragraph.images.iterator;
    for (final rune in paragraph.text.runes) {
      if (rune != _markRune) {
        buffer.writeCharCode(rune);
        continue;
      }
      images.moveNext();
      final size = sizes[images.current.src];
      final image = images.current._arranged(size, _modeOf(images.current, size, style));
      if (image.mode == ImageMode.inline) {
        buffer.write(imageMark);
        inline.add(image);
      } else {
        flush();
        lines.add((imageMark, [image]));
      }
    }
    flush();
  }
  return (title: chapter.title, paragraphs: _withOffsets(lines));
}

/// 样式取地址选项的 `style`，没有时取书源的；`TEXT` 或没指定样式又小于 80×80 的是行内图，加载失败的按块状显示。
ImageMode _modeOf(ContentImage image, Size? size, String? sourceStyle) {
  final style = (image.style ?? sourceStyle)?.trim().toUpperCase();
  if (size == null) return ImageMode.normal;
  if (style == 'TEXT' || ((style == null || style.isEmpty) && size.width < 80 && size.height < 80)) return ImageMode.inline;
  return switch (style) {
    'FULL' => ImageMode.full,
    'SINGLE' => ImageMode.single,
    _ => ImageMode.normal,
  };
}

List<Paragraph> _withOffsets(List<(String, List<ContentImage>)> lines) {
  var offset = 0;
  final paragraphs = <Paragraph>[];
  for (final (text, images) in lines) {
    paragraphs.add((text: text, offset: offset, images: images));
    offset += text.length + 1;
  }
  return paragraphs;
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
