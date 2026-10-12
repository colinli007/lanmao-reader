import 'dart:convert';

import '../core/errors.dart';
import '../json/json_path.dart';
import '../json/json_text.dart';
import '../text/lenient_json.dart';
import 'content.dart';
import 'rule_splitter.dart';

/// MD3 的 `AnalyzeByJSonPath`。
///
/// 内容是字符串时按 JSON 解析（json-smart 的宽松模式：先严格解析，失败再按宽松语法；仍然不是 JSON 时当作字符串值），
/// 其余内容（上一步取到的 JSON 对象、数组）直接使用。
final class AnalyzeByJsonPath {
  AnalyzeByJsonPath(Object? content) : _document = _parse(content);

  final Object? _document;

  static Object? _parse(Object? content) {
    if (content is! String) return content is RegexMatchGroups ? content.groups : content;
    try {
      return jsonDecode(content);
    } on FormatException {
      try {
        return parseLenientJson(content);
      } on FormatException {
        return content;
      }
    }
  }

  /// 取字符串。按 `&&`、`||` 切分（不认 `%%`）；单条规则先替换 `{$.x}` 内嵌规则，一个都没替换时整条按路径读取。
  String? getString(String rule) {
    if (rule.isEmpty) return null;
    final splitter = RuleSplitter(rule, code: true);
    final rules = splitter.splitRule(const ['&&', '||']);
    if (rules.length == 1) {
      splitter.resetPos();
      var result = splitter.innerRule(r'{$.', getString);
      if (result.isEmpty) {
        final value = _read(rule);
        if (value is List) {
          result = value.map(jaywayString).join('\n');
        } else if (value != null && value != _notFound) {
          result = jaywayString(value);
        }
      }
      return result;
    }
    final texts = <String>[];
    for (final rl in rules) {
      final temp = getString(rl);
      if (temp != null && temp.isNotEmpty) {
        texts.add(temp);
        if (splitter.elementsType == '||') break;
      }
    }
    return texts.join('\n');
  }

  List<String> getStringList(String rule) {
    final result = <String>[];
    if (rule.isEmpty) return result;
    final splitter = RuleSplitter(rule, code: true);
    final rules = splitter.splitRule(const ['&&', '||', '%%']);
    if (rules.length == 1) {
      splitter.resetPos();
      final st = splitter.innerRule(r'{$.', getString);
      if (st.isNotEmpty) {
        result.add(st);
        return result;
      }
      final value = _read(rule);
      // MD3 对 null 调 toString() 抛空指针后被吞掉，已经加进去的项保留
      for (final item in value is List ? value : [value]) {
        if (item == null || item == _notFound) break;
        result.add(jaywayString(item));
      }
      return result;
    }
    final results = <List<String>>[];
    for (final rl in rules) {
      final temp = getStringList(rl);
      if (temp.isNotEmpty) {
        results.add(temp);
        if (splitter.elementsType == '||') break;
      }
    }
    return _merge(results, splitter.elementsType);
  }

  /// 取单个值，路径不存在时以规则错误结束（MD3 在这里不捕获异常）。
  Object? getObject(String rule) {
    final value = _read(rule);
    if (value == _notFound) throw RuleException('JSONPath 取不到值：$rule');
    return value;
  }

  /// 取列表：结果不是数组时为空列表。
  List<Object?> getList(String rule) {
    if (rule.isEmpty) return [];
    final splitter = RuleSplitter(rule, code: true);
    final rules = splitter.splitRule(const ['&&', '||', '%%']);
    if (rules.length == 1) {
      final value = _read(rules.single);
      return value is List ? value : [];
    }
    final results = <List<Object?>>[];
    for (final rl in rules) {
      final temp = getList(rl);
      if (temp.isNotEmpty) {
        results.add(temp);
        if (splitter.elementsType == '||') break;
      }
    }
    if (splitter.elementsType == '%%') {
      return [
        if (results.isNotEmpty)
          for (var i = 0; i < results.first.length; i++)
            for (final temp in results)
              if (i < temp.length && temp[i] != null) temp[i],
      ];
    }
    return [for (final temp in results) ...temp];
  }

  /// Jayway 的 `read`。路径不合法或取不到时返回 [_notFound]。
  Object? _read(String rule) {
    try {
      return JsonPath.parse(rule).read(_document);
    } on FormatException {
      return _notFound;
    } on JsonPathNotFound {
      return _notFound;
    }
  }

  static List<String> _merge(List<List<String>> results, String type) {
    if (type == '%%') {
      return [
        if (results.isNotEmpty)
          for (var i = 0; i < results.first.length; i++)
            for (final temp in results)
              if (i < temp.length) temp[i],
      ];
    }
    return [for (final temp in results) ...temp];
  }
}

/// 路径取不到值。
const Object _notFound = Object();
