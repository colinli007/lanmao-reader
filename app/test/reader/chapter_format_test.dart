import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanmao_reader/reader/chapter_format.dart';

void main() {
  test('分段、去掉首尾空白（含全角空格）、丢弃空段；缩进不在正文里', () {
    final chapter = formatChapter('第一章', '　第一段  \n\n\n第二段');
    expect([for (final p in chapter.paragraphs) p.text], ['第一段', '第二段']);
  });

  test('第一段和章节名相同时去掉', () {
    final chapter = formatChapter('第一章 开始', ' 第一章 开始 \r\n正文');
    expect([for (final p in chapter.paragraphs) p.text], ['正文']);
  });

  test('图片标签换成占位字符，地址和选项记在段落上', () {
    final chapter = formatChapter('t', '前<IMG src="a.png">后\n<img src="b.png,{"style":"full","width":"50%"}"/>');
    expect([for (final p in chapter.paragraphs) p.text], ['前$imageMark后', imageMark]);
    expect([for (final p in chapter.paragraphs) for (final i in p.images) i.src], ['a.png', 'b.png,{"style":"full","width":"50%"}']);
    final b = chapter.paragraphs[1].images.single;
    expect((b.style, b.width), ('full', '50%'));
    expect(imageSourcesOf(chapter), {'a.png', 'b.png,{"style":"full","width":"50%"}'});
  });

  group('量完尺寸以后', () {
    List<String> texts(FormattedChapter c) => [for (final p in c.paragraphs) p.text];

    test('大图单独成段，前后的文字各自成段，偏移按拆开后的段落算', () {
      final raw = formatChapter('t', '前文<img src="big.jpg">后文\n下一段');
      final chapter = arrangeImages(raw, {'big.jpg': const Size(600, 400)});
      expect(texts(chapter), ['前文', imageMark, '后文', '下一段']);
      expect([for (final p in chapter.paragraphs) p.offset], [0, 3, 5, 8]);
      final image = blockImageOf(chapter.paragraphs[1])!;
      expect((image.size, image.mode), (const Size(600, 400), ImageMode.normal));
      expect(blockImageOf(chapter.paragraphs[0]), isNull);
    });

    test('小于 80×80、没有指定样式的是行内图，留在文字里', () {
      final chapter = arrangeImages(formatChapter('t', '他<img src="z.png">了一眼'), {'z.png': const Size(20, 20)});
      expect(texts(chapter), ['他$imageMark了一眼']);
      expect(chapter.paragraphs.single.images.single.mode, ImageMode.inline);
      expect(blockImageOf(chapter.paragraphs.single), isNull);
    });

    test('样式：选项优先于书源；TEXT 不分大小写是行内；不认识的按默认；加载失败按块状', () {
      final raw = formatChapter('t', [
        '<img src="a.png">',
        '<img src="b.png,{"style":"single"}">',
        '<img src="c.png,{"style":"Text"}">',
        '<img src="d.png,{"style":"weird"}">',
        '<img src="e.png">',
      ].join('\n'));
      final big = const Size(600, 400);
      final chapter = arrangeImages(raw, {'a.png': big, 'b.png,{"style":"single"}': big, 'c.png,{"style":"Text"}': big, 'd.png,{"style":"weird"}': big}, style: 'FULL');
      expect([for (final p in chapter.paragraphs) p.images.single.mode], [
        ImageMode.full,
        ImageMode.single,
        ImageMode.inline,
        ImageMode.normal,
        ImageMode.normal,
      ]);
      expect(chapter.paragraphs.last.images.single.failed, isTrue);
    });

    test('选项不是 JSON 时当作没有选项', () {
      final image = formatChapter('t', '<img src="a.png,{bad}">').paragraphs.single.images.single;
      expect((image.src, image.style, image.width), ('a.png,{bad}', null, null));
    });
  });

  test('偏移和排版后的正文一一对应', () {
    final chapter = formatChapter('t', '甲\n乙乙\n丙');
    final text = chapter.paragraphs.map((p) => p.text).join('\n');
    // 基准是各段以换行连接、不含缩进和章节名的文字
    expect(text, '甲\n乙乙\n丙');
    expect([for (final p in chapter.paragraphs) p.offset], [0, 2, 5]);
    for (final p in chapter.paragraphs) {
      expect(text.substring(p.offset, p.offset + p.text.length), p.text);
    }
    expect(paragraphAt(chapter.paragraphs, 0), 0);
    expect(paragraphAt(chapter.paragraphs, chapter.paragraphs[1].offset), 1);
    expect(paragraphAt(chapter.paragraphs, chapter.paragraphs[1].offset + 2), 1);
    expect(paragraphAt(chapter.paragraphs, 999), 2);
  });
}
