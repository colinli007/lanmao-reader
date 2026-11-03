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

  test('图片标签换成占位', () {
    final chapter = formatChapter('t', '前<IMG src="a.png">后\n<img src="b.png"/>');
    expect([for (final p in chapter.paragraphs) p.text], ['前[图片]后', '[图片]']);
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
