import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/library/relocate.dart';

import '../support/fixtures.dart';

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
}
