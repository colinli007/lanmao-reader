/// JsoupXpath 2.5.5（MD3 用的 XPath 库）的移植，作用在 `package:html` 的 DOM 上。
///
/// JsoupXpath 不是标准 XPath 1.0，这里照它的 `XpathProcessor` 逐条移植，包括它的怪异行为：
/// - `text()` 生成伪元素，取值时是合并空白、去掉首尾空白后的文本，空白文本节点得到空串；
/// - `[n]` 按「上下文里同名的兄弟元素」计序号，负数从末尾计；
/// - `position()` 返回整数，和数字字面量（小数）比较 `=` 时按字符串比较（`1` 不等于 `1.0`）；
/// - `//` 之后的名字测试用 CSS 选择，结果包含上下文元素本身；
/// - `text`、`html`、`node`、`num` 等是节点类型关键字，不能当元素名用；`div`、`mod` 运算符要写成带反引号的形式。
/// 语法或函数不支持时抛出 [FormatException]。
library;

import 'package:html/dom.dart';

import '../core/environment.dart';
import '../json/json_text.dart';
import '../regex/source_regex.dart';
import 'css_selector.dart';
import 'jsoup_text.dart';

/// 编译好的 XPath。
final class XPath {
  XPath._(this.expression, this._root);

  factory XPath.parse(String expression) => XPath._(expression, _Parser(_lex(expression)).parseMain());

  final String expression;
  final _Expr _root;

  /// JsoupXpath 的 `JXDocument.selN`：结果是元素（[Element]）或字符串、整数、小数、布尔值。
  List<Object> select(RuleEnvironment env, List<Element> context) {
    final processor = _Processor(env, context);
    final value = processor.eval(_root);
    final raw = value.value;
    if (raw is List<Node>) return [...raw];
    if (raw is List<String>) return [...raw];
    if (raw is num || raw is bool) return [raw!];
    // 单个字符串去掉首尾空白（列表里的不去）；值为 null（如 num() 取不到数字）时输出字符串 "null"
    return [value.asString()];
  }
}

/// JsoupXpath 的 `JXNode.asString`：文本伪元素取自身文本，其它元素取 outerHtml，其余值转字符串。
String xpathNodeString(Object? node) => switch (node) {
  null => '',
  String() => node,
  Element() when node.localName == _textTag => jsoupOwnText(node),
  Node() => jsoupOuterHtml(node),
  double() => javaDoubleString(node),
  _ => '$node',
};

const String _textTag = 'JX_TEXT';

// ---------------------------------------------------------------- 值

/// JsoupXpath 的 `XValue`。[value] 是 null、bool、int（Java 的 Integer/Long）、double、String、
/// `List<Node>`（Elements）或 `List<String>`。
final class _XValue {
  _XValue(this.value);

  Object? value;
  bool isAttr = false;
  bool isExprStr = false;

  bool get isBoolean => value is bool;
  bool get isNumber => value is num;
  bool get isElements => value is List<Node>;
  bool get isString => value is String;
  bool get isList => value is List<String>;

  List<Node> get elements => value as List<Node>;

  bool asBoolean() => value is bool ? value as bool : value != null && asString().trim().isNotEmpty;

  double asDouble() => switch (value) {
    final String text => double.tryParse(text.trim()) ?? (throw const FormatException('无法转成数字')),
    final num number => number.toDouble(),
    _ => throw const FormatException('无法转成数字'),
  };

  int asLong() => switch (value) {
    final String text => (double.tryParse(text.trim()) ?? (throw const FormatException('无法转成数字'))).round(),
    final num number => number.toInt(),
    _ => throw const FormatException('无法转成数字'),
  };

  String asString() => switch (value) {
    final List<Node> elements => elements.map(jsoupOwnText).join(),
    final List<String> list => list.join(','),
    final double number => javaDoubleString(number),
    null => 'null',
    final other => '$other'.trim(),
  };

  /// 去掉首尾的引号（字面量和名字都经过这一步）。
  _XValue exprStr() {
    isExprStr = true;
    var text = '$value';
    if (text.startsWith("'")) text = text.substring(1);
    if (text.startsWith('"')) text = text.substring(1);
    if (text.endsWith("'")) text = text.substring(0, text.length - 1);
    if (text.endsWith('"')) text = text.substring(0, text.length - 1);
    value = text;
    return this;
  }

  /// Java 的 valType：整数（Integer/Long）、小数、字符串等。
  Type get valType => switch (value) {
    null => Null,
    int() => int,
    double() => double,
    bool() => bool,
    String() => String,
    List<Node>() => List<Node>,
    _ => List<String>,
  };

  bool sameValue(_XValue other) {
    final a = value;
    final b = other.value;
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (a[i] is Node ? !identical(a[i], b[i]) : a[i] != b[i]) return false;
      }
      return true;
    }
    return a == b;
  }

  int compareTo(_XValue other) {
    if (sameValue(other)) return 0;
    if (other.value == null) return 1;
    if (value == null) return -1;
    if (isString) return asString().compareTo(other.asString());
    if (isNumber) return asDouble().compareTo(other.asDouble());
    throw const FormatException('无法比较的值');
  }
}

// ---------------------------------------------------------------- 作用域

final class _Scope {
  _Scope(this.context);

  List<Node> context;
  bool isRecursion = false;
  _Scope? parent;

  Node singleEl() {
    if (context.length == 1) return context.single;
    throw FormatException('当前上下文不是单个元素（${context.length} 个）');
  }
}

/// 文本伪元素在兄弟里的序号和同名总数（jsoup 里存在属性上）。
final Expando<int> _jxIndex = Expando('jxIndex');
final Expando<int> _jxCount = Expando('jxCount');

Element _textElement(String text) {
  final element = Element.tag(_textTag);
  element.append(Text(text));
  return element;
}

// ---------------------------------------------------------------- 求值

final class _Processor {
  _Processor(this.env, List<Element> root) : rootScope = _Scope([...root]) {
    scopes.add(_Scope([...root])..parent = rootScope);
  }

  final RuleEnvironment env;
  final _Scope rootScope;
  final List<_Scope> scopes = [];

  _Scope get current => scopes.last;

  _XValue eval(_Expr expr) => switch (expr) {
    _LocationPath() => _locationPath(expr),
    _Step() => _step(expr),
    _Literal() => _XValue(expr.text).exprStr(),
    _NumberLiteral() => _XValue(expr.value),
    _FunctionCall() => _functionCall(expr),
    _Binary() => _binary(expr),
    _Negate() => _XValue(-eval(expr.operand).asDouble()),
    _Union() => _union(expr),
    _FilterPath() => _filterPath(expr),
  };

  _XValue _locationPath(_LocationPath path) {
    if (!path.absolute) return _relativePath(path.steps, path.separators);
    scopes.add(_Scope(rootScope.context)..parent = current);
    if (path.leadingRecursive) current.isRecursion = true;
    final value = _relativePath(path.steps, path.separators);
    scopes.removeLast();
    return value;
  }

  /// [separators] 的第 i 项是第 i 步和第 i+1 步之间的分隔符是否为 `//`。
  _XValue _relativePath(List<_Expr> steps, List<bool> separators) {
    late _XValue last;
    for (var i = 0; i < steps.length; i++) {
      if (i > 0) current.isRecursion = separators[i - 1];
      last = eval(steps[i]);
      if (last.isElements) current.context = last.elements;
    }
    return last;
  }

  _XValue _step(_Step step) {
    if (step.abbreviated == '..') {
      final parents = <Node>[];
      final seen = Set<Node>.identity();
      for (final element in current.context) {
        final parent = element.parentNode;
        if (parent != null && seen.add(parent)) parents.add(parent);
      }
      return _XValue(parents);
    }
    if (step.abbreviated == '.') return _XValue(current.context);

    var filterByAttr = false;
    var isAxisOk = false;
    if (step.axis != null) {
      final axis = _axis(step.axis!);
      isAxisOk = true;
      if (axis.isElements) {
        current.context = axis.elements;
      } else if (axis.isAttr) {
        filterByAttr = true;
      }
    } else if (step.attribute) {
      isAxisOk = true;
      filterByAttr = true;
    }

    final nodeTest = _nodeTest(step.nodeTest);
    if (filterByAttr) {
      final attrName = nodeTest.asString();
      final context = current.context;
      if (current.isRecursion) {
        final found = CssSelector.parse('[$attrName]').selectAll(env, context);
        return _XValue(<String>[for (final element in found) jsoupAttr(element, attrName)]);
      }
      if (context.length == 1) return _XValue(jsoupAttr(context.single, attrName));
      return _XValue(<String>[for (final element in context) jsoupAttr(element, attrName)]);
    }
    if (nodeTest.isExprStr) {
      final tagName = nodeTest.asString();
      if (current.isRecursion) {
        current.context = _selectTag(current.context, tagName);
      } else {
        final next = <Node>[];
        for (final element in current.context) {
          if (isAxisOk) {
            if (_nodeName(element) == tagName || tagName == '*') next.add(element);
          } else {
            for (final child in element.nodes) {
              if (child is Element && (_nodeName(child) == tagName || tagName == '*')) next.add(child);
            }
          }
        }
        current.context = next;
      }
    } else if (nodeTest.isElements) {
      current.context = nodeTest.elements;
    } else {
      return nodeTest;
    }

    for (final predicate in step.predicates) {
      current.context = _predicate(predicate).elements;
    }
    return _XValue(current.context);
  }

  List<Node> _selectTag(List<Node> context, String tagName) {
    try {
      return CssSelector.parse(tagName).selectAll(env, context);
    } on FormatException {
      throw FormatException('不支持的 XPath 名字测试：$tagName');
    }
  }

  _XValue _nodeTest(_NodeTest test) {
    if (test.name != null) {
      final value = _XValue(test.name);
      return test.qualified ? value : value.exprStr();
    }
    return switch (test.nodeType) {
      'text' => _text(),
      'node' => _node(),
      'allText' => _XValue(<String>[
        for (final element in current.context)
          _nodeName(element) == 'script' ? jsoupData(element) : jsoupText(element),
      ]),
      'html' => _XValue(<String>[for (final element in current.context) _innerHtml(element)]),
      'outerHtml' => _XValue(<String>[for (final element in current.context) jsoupOuterHtml(element)]),
      'num' => _num(),
      final type => throw FormatException('不支持的节点类型 $type()'),
    };
  }

  _XValue _text() {
    final context = current.context;
    final result = <Node>[];
    if (context.isEmpty) return _XValue(result);
    if (current.isRecursion) {
      // 按（深度, 父节点）给文本节点编号
      final counters = <(int, Node?), int>{};
      final keys = Expando<(int, Node?)>();
      for (final element in context) {
        void visit(Node node, int depth) {
          if (node is Text && !_isDataText(node)) {
            final key = (depth, node.parentNode);
            final index = (counters[key] ?? 0) + 1;
            counters[key] = index;
            final data = _textElement(node.data)..parentNode = node.parentNode;
            _jxIndex[data] = index;
            keys[data] = key;
            result.add(data);
          }
          for (final child in node.nodes) {
            visit(child, depth + 1);
          }
        }

        visit(element, 0);
      }
      for (final data in result) {
        _jxCount[data] = counters[keys[data]];
      }
    } else {
      for (final element in context) {
        if (_nodeName(element) == 'script') {
          final data = _textElement(jsoupData(element));
          _jxIndex[data] = 1;
          _jxCount[data] = 1;
          result.add(data);
        } else {
          final texts = [
            for (final child in element.nodes)
              if (child is Text && !_isDataText(child)) child,
          ];
          for (var i = 0; i < texts.length; i++) {
            final data = _textElement(texts[i].data);
            _jxIndex[data] = i + 1;
            _jxCount[data] = texts.length;
            result.add(data);
          }
        }
      }
    }
    return _XValue(result);
  }

  _XValue _node() {
    final result = <Node>[];
    for (final element in current.context) {
      result.addAll(element.nodes.whereType<Element>());
      // JsoupXpath 在这里 new Element("")，jsoup 不接受空标签名，直接报错
      if (jsoupOwnText(element).trim().isNotEmpty) throw const FormatException('node() 不支持有文本的元素');
    }
    return _XValue(result);
  }

  _XValue _num() {
    final whole = [
      for (final element in current.context)
        _nodeName(element) == 'script' ? jsoupData(element) : jsoupText(element),
    ].join();
    final match = RegExp(r'\d*\.?\d+').firstMatch(whole);
    if (match == null) return _XValue(null);
    final number = double.parse(match.group(0)!);
    return number == number.truncateToDouble() ? _XValue(number.toInt()) : _XValue(number);
  }

  _XValue _axis(String name) {
    final context = current.context;
    List<Node> elements;
    switch (name) {
      case 'attribute':
        return _XValue(null)..isAttr = true;
      case 'self':
        elements = context;
      case 'child':
        elements = [for (final element in context) ...element.nodes.whereType<Element>()];
      case 'parent':
        elements = [
          for (final element in context)
            if (element.parentNode case final parent?) parent,
        ];
      case 'ancestor':
        elements = [for (final element in context) ..._parents(element)];
      case 'ancestor-or-self':
        elements = [
          for (final element in context) ...[..._parents(element), element],
        ];
      case 'descendant' || 'descendant-or-self':
        final seen = Set<Node>.identity();
        elements = [];
        for (final element in context) {
          for (final node in _allElements(element)) {
            if (name == 'descendant' && identical(node, element)) continue;
            if (seen.add(node)) elements.add(node);
          }
        }
      case 'following-sibling':
        elements = [for (final element in context) ..._siblings(element, forward: true)];
      case 'preceding-sibling':
        elements = [for (final element in context) ..._siblings(element, forward: false)];
      case 'following-sibling-one':
        elements = [
          for (final element in context)
            if (_elementSibling(element, 1) case final next?) next,
        ];
      case 'preceding-sibling-one':
        elements = [
          for (final element in context)
            if (_elementSibling(element, -1) case final previous?) previous,
        ];
      case 'following':
        elements = [
          for (final element in context) ...[
            for (final parent in _parents(element))
              for (final sibling in _siblings(parent, forward: true)) ..._allElements(sibling),
            for (final sibling in _siblings(element, forward: true)) ..._allElements(sibling),
          ],
        ];
      case 'preceding':
        elements = [
          for (final element in context) ...[
            for (final parent in _parents(element)) ..._siblings(parent, forward: false),
            ..._siblings(element, forward: false),
          ],
        ];
      default:
        throw FormatException('不支持的轴 $name');
    }
    return _XValue(elements);
  }

  _XValue _predicate(_Expr expr) {
    final next = <Node>[];
    final context = current.context;
    final contextSet = Set<Node>.identity()..addAll(context);
    final (indexMap, countMap) = _predicateIndices(context, contextSet);
    for (final element in context) {
      scopes.add(_Scope([element])..parent = current);
      final value = eval(expr);
      scopes.removeLast();
      if (value.isNumber) {
        var index = value.asLong();
        final isText = _nodeName(element) == _textTag;
        if (index < 0) {
          final count = isText ? (_jxCount[element] ?? -1) : (countMap[element] ?? _sameTagCount(element, contextSet));
          index = count + index + 1;
          if (index < 0) index = 1;
        }
        final position = isText ? (_jxIndex[element] ?? -1) : (indexMap[element] ?? _sameTagIndex(element, contextSet));
        if (index == position) next.add(element);
      } else if (value.isBoolean) {
        if (value.value == true) next.add(element);
      } else if (value.isString) {
        if (value.asString().trim().isNotEmpty) next.add(element);
      } else if (value.isElements) {
        if (value.elements.isNotEmpty) next.add(element);
      } else if (value.isList) {
        if ((value.value as List<String>).isNotEmpty) next.add(element);
      } else {
        throw FormatException('谓词的值无法判断：${value.value}');
      }
    }
    return _XValue(next);
  }

  /// 每个元素在父元素里、上下文中同名元素的序号和总数。
  (Map<Node, int>, Map<Node, int>) _predicateIndices(List<Node> context, Set<Node> contextSet) {
    final indexMap = Map<Node, int>.identity();
    final countMap = Map<Node, int>.identity();
    final parents = <Node>[];
    final seen = Set<Node>.identity();
    for (final element in context) {
      final parent = element.parentNode;
      if (parent != null && seen.add(parent)) parents.add(parent);
    }
    for (final parent in parents) {
      final children = parent.nodes.whereType<Element>().where(contextSet.contains).toList();
      final totals = <String, int>{};
      for (final child in children) {
        totals.update(_nodeName(child), (count) => count + 1, ifAbsent: () => 1);
      }
      final counters = <String, int>{};
      for (final child in children) {
        final tag = _nodeName(child);
        indexMap[child] = counters.update(tag, (count) => count + 1, ifAbsent: () => 1);
        countMap[child] = totals[tag]!;
      }
    }
    return (indexMap, countMap);
  }

  int _sameTagIndex(Node element, Set<Node> contextSet) {
    final parent = element.parentNode;
    if (parent == null) throw const FormatException('元素没有父元素');
    var index = 1;
    for (final child in parent.nodes.whereType<Element>()) {
      if (_nodeName(child) == _nodeName(element) && contextSet.contains(child)) {
        if (identical(child, element)) break;
        index++;
      }
    }
    return index;
  }

  /// `parent.getElementsByTag(tag)` 里属于上下文的个数（含更深的后代，和 JsoupXpath 一致）。
  int _sameTagCount(Node element, Set<Node> contextSet) {
    final parent = element.parentNode;
    if (parent == null) throw const FormatException('元素没有父元素');
    final name = _nodeName(element).toLowerCase();
    return _allElements(parent).where((node) => _nodeName(node).toLowerCase() == name && contextSet.contains(node)).length;
  }

  _XValue _functionCall(_FunctionCall call) {
    final params = <_XValue?>[];
    for (final arg in call.args) {
      scopes.add(_Scope(current.context)..parent = current);
      params.add(eval(arg));
      scopes.removeLast();
    }
    _XValue param(int i) => i < params.length && params[i] != null ? params[i]! : throw FormatException('${call.name} 缺少参数');
    switch (call.name) {
      case 'concat':
        return _XValue(params.map((p) => p!.asString()).join());
      case 'contains':
        return _XValue(param(0).asString().contains(param(1).asString()));
      case 'starts-with':
        return _XValue(param(0).asString().startsWith(param(1).asString()));
      case 'not':
        if (params.length != 1) throw const FormatException('not() 只接受一个参数');
        return _XValue(!param(0).asBoolean());
      case 'count':
        if (params.isEmpty) return _XValue(0);
        if (!param(0).isElements) throw const FormatException('count() 的参数不是元素');
        return _XValue(param(0).elements.length);
      case 'string-length':
        return _XValue(params.isEmpty ? 0 : param(0).asString().length);
      case 'first':
        return _XValue(1);
      case 'position':
        final element = current.singleEl();
        final parentContext = Set<Node>.identity()..addAll(current.parent!.context);
        return _XValue(_sameTagIndex(element, parentContext));
      case 'last':
        final element = current.singleEl();
        final parentContext = Set<Node>.identity()..addAll(current.parent!.context);
        return _XValue(_sameTagCount(element, parentContext));
      // 这两个函数取第 3 个参数时不检查个数，只给两个参数会越界报错
      case 'substring':
        final target = param(0).asString();
        final start = (param(1).asLong() - 1).clamp(0, 1 << 31);
        final end = (start + param(2).asLong()).clamp(0, target.length);
        return _XValue(_substring(target, start, end));
      case 'substring-ex':
        return _XValue(_substring(param(0).asString(), param(1).asLong(), param(2).asLong()));
      case 'substring-after':
        final target = param(0).asString();
        final sep = param(1).asString();
        final index = target.indexOf(sep);
        return _XValue(index < 0 ? '' : target.substring(index + sep.length));
      case 'substring-before':
        final target = param(0).asString();
        final sep = param(1).asString();
        final index = sep.isEmpty ? 0 : target.indexOf(sep);
        return _XValue(index < 0 ? target : target.substring(0, index));
      case 'substring-after-last':
        final target = param(0).asString();
        final sep = param(1).asString();
        final index = target.lastIndexOf(sep);
        return _XValue(sep.isEmpty || index < 0 || index == target.length - sep.length ? '' : target.substring(index + sep.length));
      case 'substring-before-last':
        final target = param(0).asString();
        final sep = param(1).asString();
        final index = target.lastIndexOf(sep);
        return _XValue(sep.isEmpty || index < 0 ? target : target.substring(0, index));
      case 'sum':
        var total = 0.0;
        for (final p in params) {
          if (p!.isNumber) total += p.asDouble();
          if (p.isString) total += double.tryParse(p.asString()) ?? (throw const FormatException('sum() 的参数不是数字'));
          if (p.isElements) {
            for (final element in p.elements) {
              total += double.tryParse(jsoupOwnText(element)) ?? (throw const FormatException('sum() 的参数不是数字'));
            }
          }
        }
        return total == total.truncateToDouble() ? _XValue(total.toInt()) : _XValue(total);
      default:
        throw FormatException('不支持的函数 ${call.name}()');
    }
  }

  /// commons-lang3 的 `StringUtils.substring`：负数从末尾计，越界时截断。
  static String _substring(String text, int start, int end) {
    if (end < 0) end += text.length;
    if (start < 0) start += text.length;
    if (end > text.length) end = text.length;
    if (start > end) return '';
    if (start < 0) start = 0;
    if (end < 0) end = 0;
    return text.substring(start, end);
  }

  _XValue _binary(_Binary expr) {
    switch (expr.op) {
      case 'or':
        var result = eval(expr.left).asBoolean();
        result = eval(expr.right).asBoolean() | result;
        return _XValue(result);
      case 'and':
        var result = eval(expr.left).asBoolean();
        result = eval(expr.right).asBoolean() & result;
        return _XValue(result);
    }
    final left = eval(expr.left);
    final right = eval(expr.right);
    switch (expr.op) {
      case '=' || '!=':
        final equal = left.valType == right.valType ? left.sameValue(right) : left.asString() == right.asString();
        return _XValue(expr.op == '=' ? equal : !equal);
      case '>':
        return _XValue(left.compareTo(right) > 0);
      case '>=':
        return _XValue(left.compareTo(right) >= 0);
      case '<':
        return _XValue(left.compareTo(right) < 0);
      case '<=':
        return _XValue(left.compareTo(right) <= 0);
      case '^=':
        return _XValue(left.asString().startsWith(right.asString()));
      case r'$=':
        return _XValue(left.asString().endsWith(right.asString()));
      case '*=':
        return _XValue(left.asString().contains(right.asString()));
      case '~=' || '!~':
        final regex = SourceRegex.tryCompile(right.asString()) ?? (throw FormatException('正则无法编译：${right.asString()}'));
        final matches = regex.matchesEntire(env, left.asString());
        return _XValue(expr.op == '~=' ? matches : !matches);
      case '+':
        return _XValue(left.asDouble() + right.asDouble());
      case '-':
        return _XValue(left.asDouble() - right.asDouble());
      case '*':
        return _XValue(left.asDouble() * right.asDouble());
      case 'div':
        return _XValue(left.asDouble() / right.asDouble());
      case 'mod':
        return _XValue(left.asDouble().remainder(right.asDouble()));
      default:
        throw FormatException('未知的运算符 ${expr.op}');
    }
  }

  _XValue _union(_Union expr) {
    final left = eval(expr.left);
    scopes.add(_Scope(current.parent!.context)..parent = current.parent);
    final right = eval(expr.right);
    scopes.removeLast();
    Element textOf(String text) => Element.tag('V')..append(Text(text));
    if (left.isElements) {
      return _XValue([...left.elements, if (right.isElements) ...right.elements else textOf(right.asString())]);
    }
    if (left.isString) {
      if (right.isElements) return _XValue([...right.elements, textOf(left.asString())]);
      return _XValue(left.asString() + right.asString());
    }
    if (left.isBoolean) {
      if (right.isBoolean) return _XValue((left.value as bool) | (right.value as bool));
      if (right.isElements) return _XValue([...right.elements, textOf(left.asString())]);
      if (right.isString) return _XValue('${left.value}${right.asString()}');
      throw const FormatException('无法合并的值');
    }
    if (left.isNumber) {
      if (right.isString) return _XValue('${javaDoubleString(left.asDouble())}${right.asString()}');
      if (right.isElements) return _XValue([...right.elements, textOf(left.asString())]);
      throw const FormatException('无法合并的值');
    }
    return _XValue([
      if (left.asString().trim().isNotEmpty) left.asString(),
      if (right.asString().trim().isNotEmpty) right.asString(),
    ].join(','));
  }

  _XValue _filterPath(_FilterPath expr) {
    // JsoupXpath 在有后续路径时不求值前面的表达式，直接从当前上下文走后续路径
    if (expr.recursive) current.isRecursion = true;
    return _relativePath(expr.steps, expr.separators);
  }
}

String _nodeName(Node node) => node is Element ? node.localName ?? '' : '#root';

bool _isDataText(Text text) {
  final parent = text.parentNode;
  return parent is Element && (parent.localName == 'script' || parent.localName == 'style');
}

String _innerHtml(Node element) {
  if (element is! Element) return jsoupOuterHtml(element);
  final html = element.nodes.map(jsoupOuterHtml).join();
  return html.trim();
}

List<Node> _parents(Node node) {
  final parents = <Node>[];
  var current = node.parent;
  while (current != null) {
    parents.add(current);
    current = current.parent;
  }
  return parents;
}

/// jsoup 的 `getAllElements`：自己和全部后代元素，先序。
List<Node> _allElements(Node root) {
  final result = <Node>[root];
  void visit(Node node) {
    for (final child in node.nodes) {
      if (child is Element) {
        result.add(child);
        visit(child);
      }
    }
  }

  visit(root);
  return result;
}

/// 兄弟节点：元素原样，文本节点变成内容为其文本的 `text` 元素。
List<Node> _siblings(Node node, {required bool forward}) {
  final parent = node.parentNode;
  if (parent == null) return [];
  final nodes = parent.nodes;
  final index = nodes.indexOf(node);
  final range = forward ? nodes.skip(index + 1) : nodes.take(index).toList().reversed;
  return [
    for (final sibling in range)
      if (sibling is Element)
        sibling
      else if (sibling is Text)
        Element.tag('text')..append(Text(jsoupNormaliseWhitespace(sibling.data))),
  ];
}

Node? _elementSibling(Node node, int direction) {
  final parent = node.parentNode;
  if (parent == null) return null;
  final siblings = parent.nodes.whereType<Element>().toList();
  final index = siblings.indexOf(node as Element) + direction;
  return index >= 0 && index < siblings.length ? siblings[index] : null;
}

// ---------------------------------------------------------------- 语法树

sealed class _Expr {}

final class _LocationPath extends _Expr {
  _LocationPath(this.absolute, this.leadingRecursive, this.steps, this.separators);

  final bool absolute;
  final bool leadingRecursive;
  final List<_Expr> steps;
  final List<bool> separators;
}

final class _Step extends _Expr {
  _Step({this.abbreviated, this.axis, this.attribute = false, required this.nodeTest, this.predicates = const []});

  final String? abbreviated;
  final String? axis;
  final bool attribute;
  final _NodeTest nodeTest;
  final List<_Expr> predicates;
}

final class _NodeTest {
  const _NodeTest({this.name, this.qualified = false, this.nodeType});

  final String? name;

  /// 带前缀的名字（`a:b`），JsoupXpath 不当作名字测试。
  final bool qualified;
  final String? nodeType;
}

final class _Literal extends _Expr {
  _Literal(this.text);

  final String text;
}

final class _NumberLiteral extends _Expr {
  _NumberLiteral(this.value);

  final double value;
}

final class _FunctionCall extends _Expr {
  _FunctionCall(this.name, this.args);

  final String name;
  final List<_Expr> args;
}

final class _Binary extends _Expr {
  _Binary(this.op, this.left, this.right);

  final String op;
  final _Expr left;
  final _Expr right;
}

final class _Negate extends _Expr {
  _Negate(this.operand);

  final _Expr operand;
}

final class _Union extends _Expr {
  _Union(this.left, this.right);

  final _Expr left;
  final _Expr right;
}

/// `表达式/路径`：JsoupXpath 只走后面的路径。
final class _FilterPath extends _Expr {
  _FilterPath(this.recursive, this.steps, this.separators);

  final bool recursive;
  final List<_Expr> steps;
  final List<bool> separators;
}

// ---------------------------------------------------------------- 词法

enum _T { slash, doubleSlash, lpar, rpar, lbrac, rbrac, minus, plus, dot, dotDot, star, div, mod, at, comma, pipe, op, colon, cc, literal, number, nodeType, axisName, name, or, and, dollar, end }

final class _Token {
  const _Token(this.type, this.text);

  final _T type;
  final String text;
}

const List<String> _nodeTypes = ['comment', 'text', 'processing-instruction', 'node', 'num', 'allText', 'outerHtml', 'html'];
const List<String> _axisNames = [
  'ancestor', 'ancestor-or-self', 'attribute', 'child', 'descendant', 'descendant-or-self', 'following', //
  'following-sibling', 'namespace', 'parent', 'preceding', 'preceding-sibling', 'self', 'following-sibling-one',
  'preceding-sibling-one', 'sibling',
];

final RegExp _ncName = RegExp(r'[A-Za-z_À-ÖØ-öø-˿Ͱ-ͽͿ-῿‌-‍⁰-↏Ⰰ-⿯、-퟿豈-﷏ﷰ-�][A-Za-z_À-ÖØ-öø-˿Ͱ-ͽͿ-῿‌-‍⁰-↏Ⰰ-⿯、-퟿豈-﷏ﷰ-�\-.0-9·̀-ͯ‿-⁀]*');
final RegExp _number = RegExp(r'\d+(\.\d*)?|\.\d+');

List<_Token> _lex(String text) {
  final tokens = <_Token>[];
  var pos = 0;
  const fixed = [
    ('//', _T.doubleSlash), ('/', _T.slash), ('(', _T.lpar), (')', _T.rpar), ('[', _T.lbrac), (']', _T.rbrac), //
    ('`div`', _T.div), ('`mod`', _T.mod), ('..', _T.dotDot), ('@', _T.at), (',', _T.comma), ('|', _T.pipe),
    ('<=', _T.op), ('>=', _T.op), ('!=', _T.op), ('^=', _T.op), (r'$=', _T.op), ('*=', _T.op), ('~=', _T.op),
    ('!~', _T.op), ('<', _T.op), ('>', _T.op), ('=', _T.op), ('::', _T.cc), (':', _T.colon), ('-', _T.minus),
    ('+', _T.plus), ('*', _T.star), (r'$', _T.dollar),
  ];
  outer:
  while (pos < text.length) {
    final c = text[pos];
    if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
      pos++;
      continue;
    }
    if (c == '"' || c == "'") {
      final end = text.indexOf(c, pos + 1);
      if (end < 0) throw FormatException('字符串没有结束', text, pos);
      tokens.add(_Token(_T.literal, text.substring(pos, end + 1)));
      pos = end + 1;
      continue;
    }
    // 名字和数字取最长匹配；和关键字等长时关键字优先（ANTLR 词法规则的顺序）
    final number = _number.matchAsPrefix(text, pos);
    final name = _ncName.matchAsPrefix(text, pos);
    if (number != null && (name == null || number.end >= name.end)) {
      tokens.add(_Token(_T.number, number.group(0)!));
      pos = number.end;
      continue;
    }
    if (name != null) {
      final word = name.group(0)!;
      final keyword = word == 'or' ? _T.or : (word == 'and' ? _T.and : null);
      final type = keyword ??
          (_nodeTypes.contains(word) ? _T.nodeType : (_axisNames.contains(word) ? _T.axisName : _T.name));
      tokens.add(_Token(type, word));
      pos = name.end;
      continue;
    }
    if (c == '.') {
      tokens.add(_Token(text.startsWith('..', pos) ? _T.dotDot : _T.dot, text.startsWith('..', pos) ? '..' : '.'));
      pos += tokens.last.text.length;
      continue;
    }
    for (final (symbol, type) in fixed) {
      if (text.startsWith(symbol, pos)) {
        tokens.add(_Token(type, symbol));
        pos += symbol.length;
        continue outer;
      }
    }
    // ANTLR 的词法器遇到不认识的字符时报告后跳过，不中断
    pos++;
  }
  tokens.add(const _Token(_T.end, ''));
  return tokens;
}

// ---------------------------------------------------------------- 语法分析

final class _Parser {
  _Parser(this.tokens);

  final List<_Token> tokens;
  int pos = 0;

  _Token get peek => tokens[pos];
  _Token peekAt(int offset) => tokens[(pos + offset).clamp(0, tokens.length - 1)];

  _Token take(_T type) {
    if (peek.type != type) throw FormatException('XPath 语法错误：期望 $type，遇到「${peek.text}」');
    return tokens[pos++];
  }

  bool accept(_T type) {
    if (peek.type != type) return false;
    pos++;
    return true;
  }

  /// JsoupXpath 的语法规则是 `main: expr`，没有要求到结尾，后面多出来的内容被忽略。
  _Expr parseMain() => _orExpr();

  _Expr _orExpr() {
    var left = _andExpr();
    while (accept(_T.or)) {
      left = _Binary('or', left, _andExpr());
    }
    return left;
  }

  _Expr _andExpr() {
    var left = _equalityExpr();
    while (accept(_T.and)) {
      left = _Binary('and', left, _equalityExpr());
    }
    return left;
  }

  _Expr _equalityExpr() {
    final left = _relationalExpr();
    if (peek.type == _T.op && (peek.text == '=' || peek.text == '!=')) {
      final op = tokens[pos++].text;
      final right = _relationalExpr();
      if (peek.type == _T.op && (peek.text == '=' || peek.text == '!=')) {
        throw const FormatException('XPath 不支持连续的相等比较');
      }
      return _Binary(op, left, right);
    }
    return left;
  }

  static const _relationalOps = {'<', '>', '<=', '>=', '^=', r'$=', '*=', '~=', '!~'};

  _Expr _relationalExpr() {
    final left = _additiveExpr();
    if (peek.type == _T.op && _relationalOps.contains(peek.text)) {
      final op = tokens[pos++].text;
      final right = _additiveExpr();
      if (peek.type == _T.op && _relationalOps.contains(peek.text)) {
        throw const FormatException('XPath 不支持连续的比较');
      }
      return _Binary(op, left, right);
    }
    return left;
  }

  _Expr _additiveExpr() {
    var left = _multiplicativeExpr();
    while (peek.type == _T.plus || peek.type == _T.minus) {
      final op = tokens[pos++].text;
      left = _Binary(op, left, _multiplicativeExpr());
    }
    return left;
  }

  _Expr _multiplicativeExpr() {
    final left = _unaryExpr();
    if (peek.type == _T.star || peek.type == _T.div || peek.type == _T.mod) {
      final op = switch (tokens[pos++].type) {
        _T.star => '*',
        _T.div => 'div',
        _ => 'mod',
      };
      return _Binary(op, left, _multiplicativeExpr());
    }
    return left;
  }

  _Expr _unaryExpr() {
    if (accept(_T.minus)) return _Negate(_unionExpr());
    return _unionExpr();
  }

  _Expr _unionExpr() {
    final left = _pathExpr();
    if (accept(_T.pipe)) return _Union(left, _unionExpr());
    return left;
  }

  _Expr _pathExpr() {
    final type = peek.type;
    final isFilter = type == _T.literal ||
        type == _T.number ||
        type == _T.lpar ||
        type == _T.dollar ||
        ((type == _T.name || type == _T.axisName) && peekAt(1).type == _T.lpar) ||
        (type == _T.name && peekAt(1).type == _T.colon && peekAt(3).type == _T.lpar);
    if (!isFilter) return _locationPath();
    final primary = _primaryExpr();
    // 过滤表达式的谓词被 JsoupXpath 忽略，但仍要合乎语法
    while (peek.type == _T.lbrac) {
      _predicate();
    }
    if (peek.type == _T.slash || peek.type == _T.doubleSlash) {
      final recursive = tokens[pos++].type == _T.doubleSlash;
      final (steps, separators) = _relativePath();
      return _FilterPath(recursive, steps, separators);
    }
    return primary;
  }

  _Expr _primaryExpr() {
    final token = peek;
    switch (token.type) {
      case _T.literal:
        pos++;
        return _Literal(token.text);
      case _T.number:
        pos++;
        return _NumberLiteral(double.parse(token.text));
      case _T.lpar:
        pos++;
        final inner = _orExpr();
        take(_T.rpar);
        return inner;
      case _T.dollar:
        throw const FormatException('XPath 不支持变量');
      default:
        final name = _qName();
        take(_T.lpar);
        final args = <_Expr>[];
        if (peek.type != _T.rpar) {
          args.add(_orExpr());
          while (accept(_T.comma)) {
            args.add(_orExpr());
          }
        }
        take(_T.rpar);
        return _FunctionCall(name, args);
    }
  }

  String _qName() {
    final first = _ncName();
    if (peek.type == _T.colon && (peekAt(1).type == _T.name || peekAt(1).type == _T.axisName)) {
      pos++;
      return '$first:${_ncName()}';
    }
    return first;
  }

  String _ncName() {
    final token = peek;
    if (token.type != _T.name && token.type != _T.axisName) {
      throw FormatException('XPath 语法错误：期望名字，遇到「${token.text}」');
    }
    pos++;
    return token.text;
  }

  _Expr _locationPath() {
    if (peek.type == _T.slash || peek.type == _T.doubleSlash) {
      final recursive = tokens[pos++].type == _T.doubleSlash;
      final (steps, separators) = _relativePath();
      return _LocationPath(true, recursive, steps, separators);
    }
    final (steps, separators) = _relativePath();
    return _LocationPath(false, false, steps, separators);
  }

  (List<_Expr>, List<bool>) _relativePath() {
    final steps = <_Expr>[_step()];
    final separators = <bool>[];
    while (peek.type == _T.slash || peek.type == _T.doubleSlash) {
      separators.add(tokens[pos++].type == _T.doubleSlash);
      steps.add(_step());
    }
    return (steps, separators);
  }

  _Step _step() {
    if (accept(_T.dot)) return _Step(abbreviated: '.', nodeTest: const _NodeTest());
    if (accept(_T.dotDot)) return _Step(abbreviated: '..', nodeTest: const _NodeTest());
    String? axis;
    var attribute = false;
    if (peek.type == _T.axisName && peekAt(1).type == _T.cc) {
      axis = tokens[pos].text;
      pos += 2;
      if (axis == 'namespace' || axis == 'sibling') throw FormatException('不支持的轴 $axis');
    } else if (accept(_T.at)) {
      attribute = true;
    }
    final nodeTest = _nodeTest();
    final predicates = <_Expr>[];
    while (peek.type == _T.lbrac) {
      predicates.add(_predicate());
    }
    return _Step(axis: axis, attribute: attribute, nodeTest: nodeTest, predicates: predicates);
  }

  _NodeTest _nodeTest() {
    if (accept(_T.star)) return const _NodeTest(name: '*');
    if (peek.type == _T.nodeType) {
      final type = tokens[pos++].text;
      take(_T.lpar);
      if (type == 'processing-instruction') throw const FormatException('不支持 processing-instruction()');
      take(_T.rpar);
      return _NodeTest(nodeType: type);
    }
    final first = _ncName();
    if (peek.type == _T.colon) {
      pos++;
      if (accept(_T.star)) return _NodeTest(name: first);
      return _NodeTest(name: '$first:${_ncName()}', qualified: true);
    }
    return _NodeTest(name: first);
  }

  _Expr _predicate() {
    take(_T.lbrac);
    final expr = _orExpr();
    take(_T.rbrac);
    return expr;
  }
}
