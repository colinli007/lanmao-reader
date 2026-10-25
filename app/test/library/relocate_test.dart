import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/library/relocate.dart';
import 'package:novel_reader/storage/database.dart';

import '../support/fixtures.dart';

TocChapter titled(int idx, String title, {bool volume = false}) => chapter('b', idx, volume: volume).copyWith(title: title);

void main() {
  test('按地址找到当前章节：前面插入了章节时序号跟着变', () {
    final chapters = [chapter('b', 0, url: '/new1'), chapter('b', 1, url: '/new2'), for (var i = 2; i < 13; i++) chapter('b', i, url: '/${i - 2}')];
    expect(relocateChapter(chapters, index: 10, url: '/10'), 12);
  });

  test('找不到时保留原序号，超出范围取最后一章', () {
    final chapters = toc('b', 5);
    expect(relocateChapter(chapters, index: 3, url: '/gone'), 3);
    expect(relocateChapter(chapters, index: 9, url: '/gone'), 4);
    expect(relocateChapter(chapters, index: 2, url: null), 2);
    expect(relocateChapter(const [], index: 2, url: '/1'), 0);
  });

  group('章节编号和纯章节名', () {
    test('编号的各种写法', () {
      expect(parseChapterTitle('第10章 云涌'), (number: 10, name: '云涌'));
      expect(parseChapterTitle('第十章　云涌！'), (number: 10, name: '云涌'));
      expect(parseChapterTitle('第一百零五回'), (number: 105, name: ''));
      expect(parseChapterTitle('第两千章 终'), (number: 2000, name: '终'));
      expect(parseChapterTitle('第一万零三百二十一节'), (number: 10321, name: ''));
      expect(parseChapterTitle('第１２章'), (number: 12, name: ''));
      expect(parseChapterTitle('012 标题'), (number: 12, name: '标题'));
    });

    test('卷名留在纯章节名里，编号取第一处「第 N 章」', () {
      expect(parseChapterTitle('第一卷 第10章 云涌'), (number: 10, name: '第一卷云涌'));
    });

    test('没有编号', () {
      expect(parseChapterTitle('番外'), (number: null, name: '番外'));
      expect(parseChapterTitle('上架感言（必看）'), (number: null, name: '上架感言必看'));
    });
  });

  group('换书源后定位当前章节', () {
    test('章节名相同，编号写法不同', () {
      final chapters = [
        titled(0, '第一卷', volume: true),
        titled(1, '序章'),
        for (var i = 1; i <= 12; i++) titled(i + 1, i == 10 ? '第十章　云涌！' : '第$i章 其它$i'),
      ];
      expect(alignChapter(chapters, index: 10, title: '第10章 云涌'), (index: 11, matched: true));
    });

    test('章节名对不上，编号对得上', () {
      final chapters = [for (var i = 0; i < 12; i++) titled(i, i == 10 ? '第10章 风云再起' : '第$i章 其它$i')];
      expect(alignChapter(chapters, index: 3, title: '第10章 云涌'), (index: 10, matched: true));
    });

    test('同名章节取最近的，距离相同时取序号小的', () {
      final chapters = [for (var i = 0; i < 60; i++) titled(i, i == 5 || i == 52 ? '上架感言' : '第$i章 其它$i')];
      expect(alignChapter(chapters, index: 50, title: '上架感言'), (index: 52, matched: true));
      final tie = [for (var i = 0; i < 10; i++) titled(i, i == 2 || i == 6 ? '上架感言' : '第$i章 其它$i')];
      expect(alignChapter(tie, index: 4, title: '上架感言'), (index: 2, matched: true));
    });

    test('同名但编号不同不算', () {
      final chapters = [titled(0, '第1章 序'), titled(1, '第2章 开始'), titled(2, '第4章 继续')];
      expect(alignChapter(chapters, index: 5, title: '第3章 序'), (index: 2, matched: false));
    });

    test('都对不上时保留原序号，截到新目录范围内', () {
      final chapters = [for (var i = 0; i < 5; i++) titled(i, '第$i章 其它')];
      expect(alignChapter(chapters, index: 3, title: '番外'), (index: 3, matched: false));
      expect(alignChapter(chapters, index: 9, title: '番外'), (index: 4, matched: false));
    });

    test('卷不参与查找', () {
      final chapters = [titled(0, '番外', volume: true), titled(1, '第1章 开始')];
      expect(alignChapter(chapters, index: 0, title: '番外'), (index: 0, matched: false));
    });
  });
}
