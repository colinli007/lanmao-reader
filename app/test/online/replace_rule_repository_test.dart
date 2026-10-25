import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/online/replace_rule_repository.dart';
import 'package:rule_engine/rule_engine.dart';

import '../support/test_app.dart';

/// replace-rules「导入替换规则」「规则列表」「新建和编辑规则」「导出替换规则」，app-storage「重启后替换规则还在」。
void main() {
  late TestServices services;
  setUp(() async => services = await TestServices.create());
  tearDown(() => services.db.close());

  ReplaceRuleRepository repository() => services.replaceRules;
  List<String> patterns() => [for (final entry in repository().entries) entry.rule.pattern];

  const file = '[{"id": 1, "pattern": "a"}, {"id": 2, "pattern": "b"}, {"id": 3, "pattern": "c"}]';

  test('再次导入同一份规则：预览全是更新，被停用的按文件恢复启用', () async {
    final first = repository().preview(loadReplaceRules(file));
    expect((first.added, first.updated), (3, 0));
    await repository().import(first.rules);
    await repository().setEnabled(2, false);

    final again = repository().preview(loadReplaceRules(file));
    expect((again.added, again.updated), (0, 3));
    await repository().import(again.rules);
    expect(repository().entries.map((entry) => entry.enabled), [true, true, true]);
  });

  test('同一个 id 在内容里出现多次时以最后一次为准', () async {
    final preview = repository().preview(loadReplaceRules('[{"id": 1, "pattern": "a"}, {"id": 1, "pattern": "b"}]'));
    expect((preview.added, preview.rules.single.pattern), (1, 'b'));
  });

  test('按 order 从小到大排列，相同时按 id', () async {
    await services.addReplaceRules([
      {'id': 3, 'pattern': 'c', 'order': 1},
      {'id': 2, 'pattern': 'b', 'order': 1},
      {'id': 1, 'pattern': 'a', 'order': 2},
      {'id': 4, 'pattern': 'd'},
    ]);
    expect(patterns(), ['d', 'b', 'c', 'a']);
  });

  test('新建的规则启用，排在最后；编辑时其它字段和启用状态不变', () async {
    await services.addReplaceRules([
      {'id': 1, 'pattern': 'a', 'order': 5, 'group': '广告', 'timeoutMillisecond': 500},
    ]);
    await repository().save({'name': '新规则', 'pattern': 'b'});
    expect(patterns(), ['a', 'b']);
    final created = repository().entries.last;
    expect((created.enabled, created.rule.order, created.rule.id > 1), (true, 6, true));

    await repository().setEnabled(1, false);
    await repository().save({'pattern': 'x', 'isRegex': false}, editing: repository().entries.first);
    final edited = repository().entries.first;
    expect((edited.rule.pattern, edited.rule.isRegex, edited.enabled), ('x', false, false));
    expect((edited.rule.json['group'], edited.rule.timeout), ('广告', const Duration(milliseconds: 500)));
  });

  test('没有规则时新建的 order 是 0', () async {
    await repository().save({'pattern': 'a'});
    expect(repository().entries.single.rule.order, 0);
  });

  test('停用只在第一次返回真', () async {
    await services.addReplaceRules([{'id': 1, 'pattern': 'a'}]);
    expect(await Future.wait([repository().disable(1), repository().disable(1)]), [true, false]);
    expect(repository().isEnabled(1), isFalse);
  });

  test('导出后再导入：同样的规则、启用状态和顺序', () async {
    await services.addReplaceRules([
      {'id': 1, 'pattern': 'a', 'order': 2, 'extra': 'x'},
      {'id': 2, 'pattern': 'b', 'order': 1},
      {'id': 3, 'pattern': 'c', 'order': 3},
    ]);
    await repository().setEnabled(3, false);
    final exported = repository().export();
    expect((jsonDecode(exported) as List).last, containsPair('isEnabled', false));

    for (final id in [1, 2, 3]) {
      await repository().delete(id);
    }
    expect(repository().entries, isEmpty);
    await repository().import(repository().preview(loadReplaceRules(exported)).rules);
    expect(patterns(), ['b', 'a', 'c']);
    expect(repository().entries.map((entry) => entry.enabled), [true, true, false]);
    expect(repository().entries[1].rule.json['extra'], 'x');
  });

  test('重启后规则和启用状态还在', () async {
    final dir = Directory.systemTemp.createTempSync('db');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = File('${dir.path}/app.sqlite');
    var restarted = await TestServices.create(file: path);
    await restarted.addReplaceRules([{'id': 1, 'pattern': 'a'}, {'id': 2, 'pattern': 'b'}]);
    await restarted.replaceRules.setEnabled(2, false);
    await restarted.db.close();

    restarted = await TestServices.create(file: path);
    addTearDown(restarted.db.close);
    expect(restarted.replaceRules.entries.map((entry) => (entry.rule.pattern, entry.enabled)), [('a', true), ('b', false)]);
  });
}
