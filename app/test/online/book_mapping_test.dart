import 'package:flutter_test/flutter_test.dart';
import 'package:lanmao_reader/online/book_mapping.dart';
import 'package:drift/drift.dart' show Value;
import 'package:rule_engine/rule_engine.dart';

void main() {
  test('Book → 存储模型 → Book：引擎专用字段不变，保存的页面不落盘', () {
    final book = Book(bookUrl: 'https://a.com/b/1', origin: 'https://a.com', originName: 'A', variables: {'bid': '9'})
      ..name = '三体'
      ..author = '刘慈欣'
      ..intro = '简介'
      ..tocUrl = 'https://a.com/toc/1'
      ..reverseToc = true
      ..customIntro = '自定义'
      ..totalChapterNum = 12
      ..infoHtml = '<html>'
      ..tocHtml = '<html>';
    final shelf = shelfBookOf(book).copyWith(durChapterIndex: 3, durChapterTitle: const Value('第三章'));
    final back = engineBookOf(shelf);
    expect(
      (back.bookUrl, back.origin, back.originName, back.name, back.author, back.intro),
      (book.bookUrl, book.origin, book.originName, '三体', '刘慈欣', '简介'),
    );
    expect(back.variables, {'bid': '9'});
    expect((back.tocUrl, back.reverseToc, back.customIntro, back.totalChapterNum), ('https://a.com/toc/1', true, '自定义', 12));
    expect((back.durChapterIndex, back.durChapterTitle), (3, '第三章'));
    expect((back.infoHtml, back.tocHtml), (null, null));
  });

  test('BookChapter → 存储模型 → BookChapter', () {
    final chapter = BookChapter(bookUrl: 'b', baseUrl: 'https://a.com/toc/', variables: {'k': 'v'})
      ..url = '1.html,{"method":"POST"}'
      ..title = '第一章'
      ..index = 4
      ..isVolume = false
      ..isVip = true
      ..isPay = true
      ..tag = '昨天'
      ..reviewImg = 'https://a.com/r.png';
    final back = engineChapterOf(tocChapterOf(chapter));
    expect(
      (back.bookUrl, back.baseUrl, back.url, back.title, back.index, back.isVip, back.isPay, back.tag, back.reviewImg),
      ('b', 'https://a.com/toc/', '1.html,{"method":"POST"}', '第一章', 4, true, true, '昨天', 'https://a.com/r.png'),
    );
    expect(back.variables, {'k': 'v'});
    expect(chapterAbsoluteUrl(back), chapterAbsoluteUrl(chapter));
  });
}
