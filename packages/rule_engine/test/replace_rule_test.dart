import 'dart:convert';

import 'package:rule_engine/rule_engine.dart';
import 'package:test/test.dart';

import 'support/fake_environment.dart';

/// replace-rules「规则的格式」「执行替换」。
void main() {
  group('载入规则', () {
    test('缺省值', () {
      final rule = loadReplaceRules('{"id": 1, "pattern": "请记住本站.*"}').rules.single;
      expect(
        (rule.id, rule.name, rule.replacement, rule.isRegex, rule.scope, rule.excludeScope),
        (1, '', '', true, '', ''),
      );
      expect((rule.scopeContent, rule.scopeTitle, rule.isEnabled, rule.timeout), (true, false, true, const Duration(seconds: 3)));
      expect(rule.order, -2147483648);
    });

    test('超时时间不大于 0 时按 3 秒', () {
      final rules = loadReplaceRules('[{"pattern": "a", "timeoutMillisecond": 0}, {"pattern": "a", "timeoutMillisecond": 500}]').rules;
      expect(rules.map((rule) => rule.timeout), [const Duration(seconds: 3), const Duration(milliseconds: 500)]);
    });

    test('缺 id 时生成，同一批里互不相同', () {
      final rules = loadReplaceRules('[{"pattern": "a"}, {"pattern": "b"}, {"id": 7, "pattern": "c"}]').rules;
      expect(rules.map((rule) => rule.id).toSet(), hasLength(3));
      expect(rules.last.id, 7);
      expect(rules.first.json['id'], rules.first.id);
    });

    test('无法编译的正则被跳过，其它照常载入', () {
      final result = loadReplaceRules(
        jsonEncode([
          {'pattern': '[未闭合', 'isRegex': true},
          '不是对象',
          {'pattern': ''},
          {'pattern': '广告'},
        ]),
      );
      expect(result.rules.single.pattern, '广告');
      expect(result.skipped, [(index: 0, reason: '正则无法编译'), (index: 1, reason: '不是 JSON 对象'), (index: 2, reason: '替换规则为空')]);
    });

    test('普通文本规则不按正则校验', () {
      expect(loadReplaceRules('{"pattern": "[未闭合", "isRegex": false}').rules, hasLength(1));
    });

    test(r'末尾的 | 会匹配空串，\| 不会', () {
      expect(replaceRuleError('广告|', isRegex: true), '正则末尾的 | 会匹配空串');
      expect(replaceRuleError(r'广告\|', isRegex: true), isNull);
      expect(replaceRuleError('广告|', isRegex: false), isNull);
    });

    test('未知字段保留', () {
      final rule = loadReplaceRules('{"id": 1, "pattern": "a", "group": "广告", "extra": [1]}').rules.single;
      expect(rule.json['group'], '广告');
      expect(rule.json['extra'], [1]);
    });

    test('不是 JSON 时抛出 FormatException', () {
      expect(() => loadReplaceRules('<html>'), throwsFormatException);
    });
  });

  group('执行正则规则', () {
    late FakeEnvironment env;

    setUp(() => env = FakeEnvironment());
    tearDown(() => env.dispose());

    String apply(String input, String pattern, String replacement) => applyReplaceRule(env, input, pattern, replacement);

    test('删除广告', () {
      expect(apply('正文\n请记住本站域名 www.example.com\n下一段', '请记住本站.*', ''), '正文\n\n下一段');
    });

    test('引用分组', () {
      expect(apply('共 12章', r'(\d+)章', r'第$1章'), '共 第12章');
    });

    test('开头的内联标志', () {
      expect(apply('AD 和 ad', '(?i)ad', ''), ' 和 ');
    });

    test('替换串引用不存在的分组时原样返回', () {
      expect(apply('共 12章', r'(\d+)章', r'$3'), '共 12章');
    });
  });
}
