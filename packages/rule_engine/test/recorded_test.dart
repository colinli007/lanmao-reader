import 'dart:convert';
import 'dart:io';

import 'package:rule_engine/rule_engine.dart';
import 'package:test/test.dart';

import 'support/replay_environment.dart';

// 真实书源的固定样例：tool/smoke.dart --record 录下四条链路的全部响应，这里不联网重放。
// expected 里的字段是录制后对照录到的网页人工核对过的：书名、作者、章节数、首尾章节名、正文开头。
void main() {
  final files = Directory('test/fixtures/recorded').listSync().whereType<File>().where((f) => f.path.endsWith('.json'));
  for (final file in files) {
    final fixture = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    final expected = fixture['expected'] as Map<String, Object?>;
    test('${expected['case']}：${file.uri.pathSegments.last}', () {
      final env = ReplayEnvironment((fixture['records'] as List).cast<Map<String, Object?>>());
      addTearDown(env.dispose);
      final source = loadBookSources(jsonEncode(fixture['source'])).sources.single;
      final key = fixture['key'] as String;

      // 和冒烟工具同样的挑选方式：书名含搜索词的第一本，第一个不是卷的章节
      final books = searchBooks(env, source, key);
      expect(books.length, expected['searchCount']);
      final picked = books.firstWhere((b) => b.name.contains(key), orElse: () => books.first);
      final book = getBookInfo(env, source, picked.toBook());
      expect(book.name, expected['name']);
      expect(book.author, expected['author']);
      final chapters = getChapterList(env, source, book);
      expect(chapters.length, expected['chapterCount']);
      expect(chapters.first.title, expected['firstChapter']);
      expect(chapters.last.title, expected['lastChapter']);
      final first = chapters.firstWhere((c) => !c.isVolume, orElse: () => chapters.first);
      final index = chapters.indexOf(first);
      final next = index + 1 < chapters.length ? chapterAbsoluteUrl(chapters[index + 1]) : null;
      final content = getContent(env, source, book, first, nextChapterUrl: next);
      expect(content.content, startsWith(expected['contentHead'] as String));
    });
  }
}
