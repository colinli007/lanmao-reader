import 'dart:collection';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../core/environment.dart';
import '../core/errors.dart';
import '../html/css_selector.dart';
import '../html/jsoup_text.dart';
import '../html/xml_parser.dart';
import 'content.dart';
import 'rule_splitter.dart';

/// MD3 的 `AnalyzeByJSoup`：JSoup 默认语法和 `@css:` 规则。
final class AnalyzeByJSoup {
  AnalyzeByJSoup(this._env, Object? content) : _element = _parse(content);

  final RuleEnvironment _env;
  final Node _element;

  /// 元素直接使用；其余内容转成字符串后解析，以 `<?xml` 开头（不区分大小写，不去空白）时按 XML 解析。
  static Node _parse(Object? content) {
    if (content is Node) return content;
    final text = contentToString(content);
    if (text.toLowerCase().startsWith('<?xml')) return parseXml(text);
    return html_parser.parse(text);
  }

  /// 取元素列表。
  List<Node> getElements(String rule) => _getElements(_element, rule);

  /// 取字符串：多项用换行连接，没有结果时为 null。
  String? getString(String rule) {
    if (rule.isEmpty) return null;
    final list = getStringList(rule);
    if (list.isEmpty) return null;
    return list.length == 1 ? list.single : list.join('\n');
  }

  /// 只取第一项，没有时为空串。用于取地址。
  String getString0(String rule) => getStringList(rule).firstOrNull ?? '';

  List<String> getStringList(String rule) {
    final texts = <String>[];
    if (rule.isEmpty) return texts;
    final (:elementsRule, :isCss) = _sourceRule(rule);
    if (elementsRule.isEmpty) {
      texts.add(jsoupData(_element));
      return texts;
    }
    final splitter = RuleSplitter(elementsRule);
    final rules = splitter.splitRule(const ['&&', '||', '%%']);
    final results = <List<String>>[];
    for (final ruleX in rules) {
      List<String>? temp;
      if (isCss) {
        final lastIndex = ruleX.lastIndexOf('@');
        // MD3 在这里越界崩溃（substring(0, -1)）
        if (lastIndex < 0) throw RuleException('@css: 规则缺少取值方式：$ruleX');
        temp = _resultLast(_select(_element, ruleX.substring(0, lastIndex)), ruleX.substring(lastIndex + 1));
      } else {
        temp = _resultList(ruleX);
      }
      if (temp != null && temp.isNotEmpty) {
        results.add(temp);
        if (splitter.elementsType == '||') break;
      }
    }
    if (results.isNotEmpty) {
      if (splitter.elementsType == '%%') {
        for (var i = 0; i < results.first.length; i++) {
          for (final temp in results) {
            if (i < temp.length) texts.add(temp[i]);
          }
        }
      } else {
        for (final temp in results) {
          texts.addAll(temp);
        }
      }
    }
    return texts;
  }

  List<Node> _getElements(Node? temp, String rule) {
    if (temp == null || rule.isEmpty) return [];
    final (:elementsRule, :isCss) = _sourceRule(rule);
    final splitter = RuleSplitter(elementsRule);
    final rules = splitter.splitRule(const ['&&', '||', '%%']);
    final elementsList = <List<Node>>[];
    if (isCss) {
      for (final ruleStr in rules) {
        final tempS = _select(temp, ruleStr);
        elementsList.add(tempS);
        if (tempS.isNotEmpty && splitter.elementsType == '||') break;
      }
    } else {
      for (final ruleStr in rules) {
        final rsRule = RuleSplitter(ruleStr)..trim();
        final rs = rsRule.splitRule(const ['@']);
        List<Node> el;
        if (rs.length > 1) {
          el = [temp];
          for (final rl in rs) {
            el = [for (final et in el) ..._getElements(et, rl)];
          }
        } else {
          el = _ElementsSingle(_env).select(temp, ruleStr);
        }
        // 空结果也放进列表，%% 时会让结果整体为空，和 MD3 一致
        elementsList.add(el);
        if (el.isNotEmpty && splitter.elementsType == '||') break;
      }
    }
    final elements = <Node>[];
    if (elementsList.isNotEmpty) {
      if (splitter.elementsType == '%%') {
        for (var i = 0; i < elementsList.first.length; i++) {
          for (final es in elementsList) {
            if (i < es.length) elements.add(es[i]);
          }
        }
      } else {
        for (final es in elementsList) {
          elements.addAll(es);
        }
      }
    }
    return elements;
  }

  List<String>? _resultList(String ruleStr) {
    if (ruleStr.isEmpty) return null;
    var elements = <Node>[_element];
    final splitter = RuleSplitter(ruleStr)..trim();
    final rules = splitter.splitRule(const ['@']);
    final last = rules.length - 1;
    for (var i = 0; i < last; i++) {
      elements = [for (final elt in elements) ..._ElementsSingle(_env).select(elt, rules[i])];
    }
    return elements.isEmpty ? null : _resultLast(elements, rules[last]);
  }

  List<String> _resultLast(List<Node> elements, String lastRule) {
    final texts = <String>[];
    switch (lastRule) {
      case 'text':
        for (final element in elements) {
          final text = jsoupText(element);
          if (text.isNotEmpty) texts.add(text);
        }
      case 'textNodes':
        for (final element in elements) {
          final parts = [
            for (final text in jsoupTextNodes(element))
              if (_trimJava(text) case final trimmed when trimmed.isNotEmpty) trimmed,
          ];
          if (parts.isNotEmpty) texts.add(parts.join('\n'));
        }
      case 'ownText':
        for (final element in elements) {
          final text = jsoupOwnText(element);
          if (text.isNotEmpty) texts.add(text);
        }
      case 'html':
        // 先从 DOM 里删掉脚本和样式，后续规则看到的也是删过的 DOM
        for (final node in [..._select(elements, 'script'), ..._select(elements, 'style')]) {
          node.remove();
        }
        final html = jsoupOuterHtmlAll(elements);
        if (html.isNotEmpty) texts.add(html);
      case 'all':
        texts.add(jsoupOuterHtmlAll(elements));
      default:
        for (final element in elements) {
          final value = jsoupAttr(element, lastRule);
          if (value.trim().isEmpty || texts.contains(value)) continue;
          texts.add(value);
        }
    }
    return texts;
  }

  List<Node> _select(Object roots, String query) {
    final selector = _compile(query);
    return roots is Node ? selector.select(_env, roots) : selector.selectAll(_env, roots as List<Node>);
  }
}

typedef _SourceRule = ({String elementsRule, bool isCss});

/// `@CSS:` 开头（不区分大小写）的规则去掉前缀和首尾空白。
_SourceRule _sourceRule(String rule) {
  if (rule.length >= 5 && rule.substring(0, 5).toLowerCase() == '@css:') {
    return (elementsRule: _trimJava(rule.substring(5)), isCss: true);
  }
  return (elementsRule: rule, isCss: false);
}

/// 编译选择器，语法不支持时以规则错误结束（MD3 里 jsoup 抛出 SelectorParseException）。
CssSelector _compile(String query) {
  final cached = _selectorCache.remove(query);
  if (cached != null) return _selectorCache[query] = cached;
  final CssSelector selector;
  try {
    selector = CssSelector.parse(query);
  } on FormatException catch (e) {
    throw RuleException('选择器无法解析：$query（${e.message}）');
  }
  _selectorCache[query] = selector;
  if (_selectorCache.length > 256) _selectorCache.remove(_selectorCache.keys.first);
  return selector;
}

final LinkedHashMap<String, CssSelector> _selectorCache = LinkedHashMap();

/// MD3 的 `ElementsSingle`：一段选择器加索引。
///
/// 旧式索引 `.N`、`!N`、`:` 列举（从后往前解析），`[...]` 式索引支持排除、区间和步长，负数从末尾计。
final class _ElementsSingle {
  _ElementsSingle(this._env);

  final RuleEnvironment _env;

  /// `.` 选取，`!` 排除，空格表示没有索引。
  String _split = '.';
  String _beforeRule = '';
  final List<int> _indexDefault = [];

  /// 单个下标是 [int]，区间是 [_Range]。
  final List<Object> _indexes = [];

  List<Node> select(Node temp, String rule) {
    _findIndexSet(rule);

    List<Node> elements;
    if (_beforeRule.isEmpty) {
      elements = _children(temp);
    } else {
      final rules = _beforeRule.split('.');
      // MD3 在名字缺失时越界崩溃，class 和 tag 的名字为空时 jsoup 报错
      String second({bool notEmpty = false}) {
        final name = rules.length > 1 ? rules[1] : null;
        if (name == null || (notEmpty && name.isEmpty)) throw RuleException('规则缺少名字：$_beforeRule');
        return name;
      }

      elements = switch (rules[0]) {
        'children' => _children(temp),
        'class' => collectByClass(_env, temp, second(notEmpty: true)),
        'tag' => collectByTag(_env, temp, second(notEmpty: true)),
        'id' => collectById(_env, temp, second()),
        'text' => collectContainingOwnText(_env, temp, second()),
        _ => _compile(_beforeRule).select(_env, temp),
      };
    }

    final len = elements.length;
    final lastIndexes = _indexDefault.isNotEmpty ? _indexDefault.length - 1 : _indexes.length - 1;
    final indexSet = <int>{};
    if (_indexes.isEmpty) {
      for (var ix = lastIndexes; ix >= 0; ix--) {
        final it = _indexDefault[ix];
        if (it >= 0 && it < len) {
          indexSet.add(it);
        } else if (it < 0 && len >= -it) {
          indexSet.add(it + len);
        }
      }
    } else {
      for (var ix = lastIndexes; ix >= 0; ix--) {
        final index = _indexes[ix];
        if (index is _Range) {
          var start = index.start ?? 0;
          if (start < 0) start += len;
          var end = index.end ?? (len - 1);
          if (end < 0) end += len;
          // 两端在同一侧越界：无效区间
          if ((start < 0 && end < 0) || (start >= len && end >= len)) continue;
          if (start >= len) {
            start = len - 1;
          } else if (start < 0) {
            start = 0;
          }
          if (end >= len) {
            end = len - 1;
          } else if (end < 0) {
            end = 0;
          }
          if (start == end || index.step >= len) {
            indexSet.add(start);
            continue;
          }
          final step = index.step > 0 ? index.step : (-index.step < len ? index.step + len : 1);
          if (end > start) {
            for (var i = start; i <= end; i += step) {
              indexSet.add(i);
            }
          } else {
            for (var i = start; i >= end; i -= step) {
              indexSet.add(i);
            }
          }
        } else {
          final it = index as int;
          if (it >= 0 && it < len) {
            indexSet.add(it);
          } else if (it < 0 && len >= -it) {
            indexSet.add(it + len);
          }
        }
      }
    }

    if (_split == '!') {
      return [
        for (var i = 0; i < elements.length; i++)
          if (!indexSet.contains(i)) elements[i],
      ];
    }
    if (_split == '.') return [for (final i in indexSet) elements[i]];
    return elements;
  }

  /// 从后往前解析索引，设置 [_split]、[_beforeRule] 和索引列表。
  void _findIndexSet(String rule) {
    final rus = _trimJava(rule);
    if (rus.isEmpty) {
      _split = ' ';
      _beforeRule = rus;
      return;
    }
    var len = rus.length;
    int? curInt;
    var curMinus = false;
    final curList = <int?>[];
    var l = '';

    if (rus.endsWith(']')) {
      len--;
      while (len-- > 0) {
        var rl = rus[len];
        if (rl == ' ') continue;
        if (_isDigit(rl)) {
          l = rl + l;
        } else if (rl == '-') {
          curMinus = true;
        } else {
          curInt = l.isEmpty ? null : (curMinus ? -int.parse(l) : int.parse(l));
          if (rl == ':') {
            curList.add(curInt);
          } else {
            if (curList.isEmpty) {
              if (curInt == null) break;
              _indexes.add(curInt);
            } else {
              final step = curList.length == 2 ? curList.first : 1;
              // MD3 在步长为空时拆箱抛空指针
              if (step == null) throw RuleException('索引区间的步长为空：$rule');
              _indexes.add(_Range(curInt, curList.last, step));
              curList.clear();
            }
            if (rl == '!') {
              _split = '!';
              if (len == 0) throw RuleException('索引不完整：$rule');
              do {
                rl = rus[--len];
              } while (len > 0 && rl == ' ');
            }
            if (rl == '[') {
              _beforeRule = rus.substring(0, len);
              return;
            }
            if (rl != ',') break;
          }
          l = '';
          curMinus = false;
        }
      }
    } else {
      while (len-- > 0) {
        final rl = rus[len];
        if (rl == ' ') continue;
        if (_isDigit(rl)) {
          l = rl + l;
        } else if (rl == '-') {
          curMinus = true;
        } else {
          if (rl == '!' || rl == '.' || rl == ':') {
            // MD3 在这里对空串 toInt() 抛 NumberFormatException
            if (l.isEmpty) throw RuleException('索引不是数字：$rule');
            _indexDefault.add(curMinus ? -int.parse(l) : int.parse(l));
            if (rl != ':') {
              _split = rl;
              _beforeRule = rus.substring(0, len);
              return;
            }
          } else {
            break;
          }
          l = '';
          curMinus = false;
        }
      }
    }
    _split = ' ';
    _beforeRule = rus;
  }

  static List<Node> _children(Node node) => [
    for (final child in node.nodes)
      if (child is Element) child,
  ];

  static bool _isDigit(String c) => c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;
}

/// `[start:end:step]` 区间，两端可以省略。
final class _Range {
  const _Range(this.start, this.end, this.step);

  final int? start;
  final int? end;
  final int step;
}

String _trimJava(String text) {
  var start = 0;
  var end = text.length;
  while (start < end && text.codeUnitAt(start) <= 0x20) {
    start++;
  }
  while (end > start && text.codeUnitAt(end - 1) <= 0x20) {
    end--;
  }
  return text.substring(start, end);
}
