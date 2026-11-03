import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanmao_reader/storage/database.dart';

import '../support/fixtures.dart';

void main() {
  late File file;
  setUp(() => file = File('${Directory.systemTemp.createTempSync('db').path}/app.sqlite'));
  tearDown(() => file.parent.deleteSync(recursive: true));

  Future<void> seed(AppDatabase db, String url) async {
    await db.saveBrowsingBook(book(url), toc(url, 3));
    await db.putContent(ContentRow(bookUrl: url, chapterUrl: '/0.html', title: '第0章', content: '正文'));
    await db.saveProgress(url, index: 2, url: '/2.html', title: '第2章', position: 10, now: DateTime(2026));
  }

  test('重启后只剩书架上的书，浏览中的书连同目录和正文被清理', () async {
    var db = AppDatabase(NativeDatabase(file));
    await seed(db, 'shelf');
    await seed(db, 'browsing');
    await db.addToShelf('shelf', DateTime(2026));
    await db.close();

    db = AppDatabase(NativeDatabase(file));
    await db.purgeBrowsingBooks();
    expect([for (final b in await db.select(db.books).get()) b.bookUrl], ['shelf']);
    expect(await db.chaptersOf('browsing'), isEmpty);
    expect(await db.getContent('browsing', '/0.html'), isNull);
    // 加入书架只改了标志：目录、已加载的正文、进度都还在
    final shelf = (await db.getBook('shelf'))!;
    expect((shelf.inShelf, shelf.durChapterIndex, shelf.durChapterPos), (true, 2, 10));
    expect(await db.chaptersOf('shelf'), hasLength(3));
    expect((await db.getContent('shelf', '/0.html'))?.content, '正文');
    await db.close();
  });

  test('移出书架后书、目录、正文都没有它的行', () async {
    final db = AppDatabase(NativeDatabase(file));
    await seed(db, 'b');
    await db.addToShelf('b', DateTime(2026));
    await db.removeBook('b');
    expect(await db.select(db.books).get(), isEmpty);
    expect(await db.select(db.chapters).get(), isEmpty);
    expect(await db.select(db.contents).get(), isEmpty);
    await db.close();
  });
}
