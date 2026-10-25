import 'dart:async';

import 'package:blocking_bridge/blocking_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/online/online_content_source.dart';
import 'package:novel_reader/storage/database.dart';

import '../support/test_app.dart';

/// replace-rules「规则的作用范围」「执行替换」「超时停用」：OnlineContentSource.purify。
void main() {
  late TestServices services;
  setUp(() async => services = await TestServices.create());
  tearDown(() => services.db.close());

  ShelfBook book({String name = '三体', String origin = 'https://a.com'}) => ShelfBook(
    bookUrl: '$origin/book/1',
    origin: origin,
    originName: '书源',
    name: name,
    author: '刘慈欣',
    durChapterIndex: 0,
    durChapterPos: 0,
    inShelf: true,
    sourceData: '{}',
  );

  OnlineContentSource source() => OnlineContentSource(services.engine, services.repository, services.replaceRules);

  Future<String> content(String text, {ShelfBook? of}) async =>
      (await source().purify(of ?? book(), (title: '标题', content: text))).text.content;

  test('删除广告', () async {
    await services.addReplaceRules([{'id': 1, 'pattern': '请记住本站.*'}]);
    expect(await content('正文\n请记住本站域名 www.example.com\n下一段'), '正文\n\n下一段');
  });

  test('普通文本里的特殊字符按普通文字处理，不交给 worker', () async {
    await services.addReplaceRules([{'id': 1, 'pattern': '(本章完)', 'replacement': r'$1', 'isRegex': false}]);
    expect(await content('结尾(本章完)'), r'结尾$1');
    expect(services.engine.calls, isEmpty);
  });

  test('依次作用，后一条作用在前一条的结果上', () async {
    await services.addReplaceRules([
      {'id': 1, 'pattern': 'AB', 'replacement': 'C', 'order': 1},
      {'id': 2, 'pattern': 'CD', 'replacement': 'E', 'order': 2, 'isRegex': false},
    ]);
    expect(await content('ABD'), 'E');
  });

  test('只作用于某本书', () async {
    await services.addReplaceRules([{'id': 1, 'pattern': '广告', 'scope': '三体;球状闪电'}]);
    expect(await content('广告'), '');
    expect(await content('广告', of: book(name: '流浪地球')), '广告');
  });

  test('排除某个书源', () async {
    await services.addReplaceRules([{'id': 1, 'pattern': '广告', 'excludeScope': 'https://a.com'}]);
    expect(await content('广告'), '广告');
    expect(await content('广告', of: book(origin: 'https://b.com')), '');
  });

  test('停用的规则、只作用于章节名的规则不替换正文；作用于章节名的规则替换章节名', () async {
    await services.addReplaceRules([
      {'id': 1, 'pattern': '广告', 'isEnabled': false},
      {'id': 2, 'pattern': '（求月票）', 'scopeTitle': true, 'scopeContent': false},
    ]);
    final purified = await source().purify(book(), (title: '第10章 云涌（求月票）', content: '广告（求月票）'));
    expect(purified.text, (title: '第10章 云涌', content: '广告（求月票）'));
  });

  test('超时：跳过这条、停用并只提示一次，后面的规则照常执行', () async {
    await services.addReplaceRules([
      {'id': 1, 'name': '回溯', 'pattern': r'(a+)+b', 'order': 1},
      {'id': 2, 'pattern': '广告', 'order': 2},
    ]);
    // 两章同时执行同一条规则，都在它上面超时
    final timedOut = Completer<void>();
    services.engine.onReplace = (input, rule) async {
      if (rule.id != 1) return input.replaceAll(rule.pattern, '');
      await timedOut.future;
      throw TaskTimeoutException(rule.timeout);
    };
    final chapters = [source().purify(book(), (title: '', content: 'aaa广告')), source().purify(book(), (title: '', content: 'aaa广告'))];
    timedOut.complete();
    final results = await Future.wait(chapters);
    expect(results.map((r) => r.text.content), ['aaa', 'aaa']);
    expect(results.expand((r) => r.disabled), ['回溯']);
    expect(services.replaceRules.isEnabled(1), isFalse);

    // 之后的章节不再执行它
    services.engine.calls.clear();
    expect(await content('aaa广告'), 'aaa');
    expect(services.engine.calls, ['replace 广告']);
  });

  test('其它错误时这条规则不改变文字', () async {
    await services.addReplaceRules([{'id': 1, 'pattern': '广告'}]);
    services.engine.onReplace = (input, rule) => Future.error(const WorkerExitedException());
    expect(await content('广告'), '广告');
    expect(services.replaceRules.isEnabled(1), isTrue);
  });
}
