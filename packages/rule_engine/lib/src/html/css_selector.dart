/// jsoup 1.16.2 的 CSS 选择器，作用在 `package:html` 的 DOM 上。
///
/// 解析照 jsoup 的 `QueryParser` / `TokenQueue`，匹配照 `Evaluator` / `StructuralEvaluator` 移植：
/// 选择结果按文档顺序排列，包含起点元素本身；`Document` 相当于 jsoup 的根元素 `#root`。
/// `:matches`、`[attr~=正则]` 里的正则是书源提供的，走 [SourceRegex]，能被任务中止。
library;

import 'package:html/dom.dart';

import '../core/environment.dart';
import '../regex/source_regex.dart';
import 'jsoup_text.dart';

/// 编译好的选择器。语法不支持时 [CssSelector.parse] 抛出 [FormatException]。
final class CssSelector {
  CssSelector._(this.query, this._evaluator);

  factory CssSelector.parse(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) throw FormatException('选择器为空', query);
    return CssSelector._(trimmed, _QueryParser(trimmed).parse());
  }

  final String query;
  final _Evaluator _evaluator;

  /// 从 [root]（`Element` 或 `Document`）开始，按文档顺序选出全部匹配的元素，包含 [root] 本身。
  List<Node> select(RuleEnvironment env, Node root) {
    final context = _MatchContext(env);
    final result = <Node>[];
    void visit(Node node) {
      if (_evaluator.matches(context, root, node)) result.add(node);
      for (final child in node.nodes) {
        if (child is Element) visit(child);
      }
    }

    visit(root);
    return result;
  }

  /// 从多个起点选择，结果去重，保持首次出现的顺序（jsoup 的 `Elements.select`）。
  List<Node> selectAll(RuleEnvironment env, Iterable<Node> roots) {
    final seen = Set<Node>.identity();
    return [
      for (final root in roots)
        for (final node in select(env, root))
          if (seen.add(node)) node,
    ];
  }
}

/// jsoup 的 `getElementsByClass`、`getElementsByTag`、`getElementById` 的按条件收集，包含 [root] 本身。
List<Node> collectByClass(RuleEnvironment env, Node root, String className) =>
    _collect(env, root, _ClassEval(className.trim()));

List<Node> collectByTag(RuleEnvironment env, Node root, String tagName) =>
    _collect(env, root, _TagEval(tagName.trim().toLowerCase()));

List<Node> collectById(RuleEnvironment env, Node root, String id) => _collect(env, root, _IdEval(id));

/// jsoup 的 `getElementsContainingOwnText`：自身文本包含 [text]（不区分大小写）。
List<Node> collectContainingOwnText(RuleEnvironment env, Node root, String text) =>
    _collect(env, root, _ContainsTextEval(text, own: true));

List<Node> _collect(RuleEnvironment env, Node root, _Evaluator evaluator) => CssSelector._('', evaluator).select(env, root);

// ---------------------------------------------------------------- DOM 辅助

/// jsoup 的元素：`Element` 或 `Document`（`#root`）。
bool _isElementLike(Node? node) => node is Element || node is Document;

Node? _parent(Node node) {
  final parent = node.parentNode;
  return _isElementLike(parent) ? parent : null;
}

/// jsoup 的 `normalName`：标签名转小写（XML 文档保留了大小写）。
String _normalName(Node node) => jsoupTagName(node).toLowerCase();

List<Element> _elementChildren(Node node) => [
  for (final child in node.nodes)
    if (child is Element) child,
];

/// 属性名不区分大小写。没有这个属性时为 null。
String? _attribute(Node node, String key) {
  if (node is! Element) return null;
  final lower = key.toLowerCase();
  for (final MapEntry(key: name, :value) in node.attributes.entries) {
    if ('$name'.toLowerCase() == lower) return value;
  }
  return null;
}

/// jsoup `Element.attr`：没有时为空串；`abs:` 前缀按空的 baseUri 解析，只有绝对地址能取到。
String jsoupAttr(Node node, String key) {
  final value = _attribute(node, key) ?? '';
  if (value.isNotEmpty || !key.toLowerCase().startsWith('abs:')) return value;
  final relative = _attribute(node, key.substring(4));
  return relative != null && _uriScheme.hasMatch(relative) ? relative : '';
}

final RegExp _uriScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+\-.]*:');

/// jsoup `Element.hasAttr`。
bool _hasAttr(Node node, String key) {
  if (key.toLowerCase().startsWith('abs:') && jsoupAttr(node, key).isNotEmpty) return true;
  return _attribute(node, key) != null;
}

// ---------------------------------------------------------------- 匹配

final class _MatchContext {
  _MatchContext(this.env);

  final RuleEnvironment env;

  /// 结构匹配的缓存，键是 (root, 元素)；jsoup 的 `memoMatches`。
  final Map<_Evaluator, Map<Node, Map<Node, bool>>> _memo = Map.identity();

  /// 元素在兄弟元素里的下标。
  final Map<Node, int> _siblingIndex = Map.identity();

  bool memo(_Evaluator evaluator, Node root, Node element) {
    final byElement = (_memo[evaluator] ??= Map.identity())[root] ??= Map.identity();
    return byElement[element] ??= evaluator.matches(this, root, element);
  }

  int elementSiblingIndex(Node element) {
    final cached = _siblingIndex[element];
    if (cached != null) return cached;
    final parent = _parent(element);
    if (parent == null) return 0;
    final siblings = _elementChildren(parent);
    for (var i = 0; i < siblings.length; i++) {
      _siblingIndex[siblings[i]] = i;
    }
    return _siblingIndex[element]!;
  }
}

sealed class _Evaluator {
  bool matches(_MatchContext context, Node root, Node element);
}

final class _AndEval extends _Evaluator {
  _AndEval(this.evaluators);

  final List<_Evaluator> evaluators;

  @override
  bool matches(_MatchContext context, Node root, Node element) =>
      evaluators.every((evaluator) => evaluator.matches(context, root, element));
}

final class _OrEval extends _Evaluator {
  _OrEval(this.evaluators);

  final List<_Evaluator> evaluators;

  @override
  bool matches(_MatchContext context, Node root, Node element) =>
      evaluators.any((evaluator) => evaluator.matches(context, root, element));
}

final class _RootEval extends _Evaluator {
  @override
  bool matches(_MatchContext context, Node root, Node element) => identical(root, element);
}

final class _AllEval extends _Evaluator {
  @override
  bool matches(_MatchContext context, Node root, Node element) => true;
}

final class _TagEval extends _Evaluator {
  _TagEval(this.tagName);

  final String tagName;

  @override
  bool matches(_MatchContext context, Node root, Node element) => _normalName(element) == tagName;
}

final class _TagEndsWithEval extends _Evaluator {
  _TagEndsWithEval(this.suffix);

  final String suffix;

  @override
  bool matches(_MatchContext context, Node root, Node element) => _normalName(element).endsWith(suffix);
}

final class _IdEval extends _Evaluator {
  _IdEval(this.id);

  final String id;

  @override
  bool matches(_MatchContext context, Node root, Node element) => (_attribute(element, 'id') ?? '') == id;
}

/// jsoup `hasClass`：按空白切分 class 属性，不区分大小写。
final class _ClassEval extends _Evaluator {
  _ClassEval(String className) : className = className.toLowerCase();

  final String className;

  @override
  bool matches(_MatchContext context, Node root, Node element) {
    final classes = _attribute(element, 'class');
    if (classes == null || classes.isEmpty) return false;
    return classes.toLowerCase().split(_javaWhitespace).contains(className);
  }
}

final class _AttributeEval extends _Evaluator {
  _AttributeEval(this.key);

  final String key;

  @override
  bool matches(_MatchContext context, Node root, Node element) => _hasAttr(element, key);
}

final class _AttributeStartingEval extends _Evaluator {
  _AttributeStartingEval(String prefix) : prefix = prefix.toLowerCase();

  final String prefix;

  @override
  bool matches(_MatchContext context, Node root, Node element) =>
      element is Element && element.attributes.keys.any((key) => '$key'.toLowerCase().startsWith(prefix));
}

enum _ValueOp { equals, notEquals, starting, ending, containing }

/// jsoup 的 `AttributeKeyPair` 一族：值去掉引号、转小写；`=` 比较前去掉属性值首尾空白。
final class _AttributeValueEval extends _Evaluator {
  _AttributeValueEval(String key, String value, this.op) : key = key.trim().toLowerCase(), value = _pairValue(value, op);

  final String key;
  final String value;
  final _ValueOp op;

  static String _pairValue(String value, _ValueOp op) {
    if (value.isEmpty) throw const FormatException('属性值为空');
    final quoted =
        value.length >= 2 &&
        ((value.startsWith("'") && value.endsWith("'")) || (value.startsWith('"') && value.endsWith('"')));
    if (quoted) value = value.substring(1, value.length - 1);
    // ^= 和 $= 对带引号的值不去首尾空白
    final keepSpace = (op == _ValueOp.starting || op == _ValueOp.ending) && quoted;
    return keepSpace ? value.toLowerCase() : value.trim().toLowerCase();
  }

  @override
  bool matches(_MatchContext context, Node root, Node element) {
    final actual = jsoupAttr(element, key);
    return switch (op) {
      _ValueOp.equals => _hasAttr(element, key) && actual.trim().toLowerCase() == value,
      _ValueOp.notEquals => actual.toLowerCase() != value,
      _ValueOp.starting => _hasAttr(element, key) && actual.toLowerCase().startsWith(value),
      _ValueOp.ending => _hasAttr(element, key) && actual.toLowerCase().endsWith(value),
      _ValueOp.containing => _hasAttr(element, key) && actual.toLowerCase().contains(value),
    };
  }
}

final class _AttributeMatchingEval extends _Evaluator {
  _AttributeMatchingEval(String key, this.regex) : key = key.trim().toLowerCase();

  final String key;
  final SourceRegex regex;

  @override
  bool matches(_MatchContext context, Node root, Node element) =>
      _hasAttr(element, key) && regex.firstMatch(context.env, jsoupAttr(element, key)) != null;
}

enum _IndexOp { lessThan, greaterThan, equals }

final class _IndexEval extends _Evaluator {
  _IndexEval(this.index, this.op);

  final int index;
  final _IndexOp op;

  @override
  bool matches(_MatchContext context, Node root, Node element) {
    final position = context.elementSiblingIndex(element);
    return switch (op) {
      _IndexOp.lessThan => !identical(root, element) && position < index,
      _IndexOp.greaterThan => position > index,
      _IndexOp.equals => position == index,
    };
  }
}

enum _NthKind { child, lastChild, ofType, lastOfType }

final class _NthEval extends _Evaluator {
  _NthEval(this.a, this.b, this.kind);

  final int a;
  final int b;
  final _NthKind kind;

  @override
  bool matches(_MatchContext context, Node root, Node element) {
    final parent = _parent(element);
    if (parent == null || parent is Document) return false;
    final position = _position(context, parent, element);
    if (a == 0) return position == b;
    return (position - b) * a >= 0 && (position - b) % a == 0;
  }

  int _position(_MatchContext context, Node parent, Node element) {
    switch (kind) {
      case _NthKind.child:
        return context.elementSiblingIndex(element) + 1;
      case _NthKind.lastChild:
        return _elementChildren(parent).length - context.elementSiblingIndex(element);
      case _NthKind.ofType:
        final name = _normalName(element);
        var position = 0;
        for (final child in parent.nodes) {
          if (child is Element && _normalName(child) == name) position++;
          if (identical(child, element)) break;
        }
        return position;
      case _NthKind.lastOfType:
        final name = _normalName(element);
        final siblings = _elementChildren(parent);
        return siblings.skip(context.elementSiblingIndex(element)).where((e) => _normalName(e) == name).length;
    }
  }
}

enum _ChildKind { first, last, only, onlyOfType }

final class _ChildEval extends _Evaluator {
  _ChildEval(this.kind);

  final _ChildKind kind;

  @override
  bool matches(_MatchContext context, Node root, Node element) {
    final parent = _parent(element);
    if (parent == null || parent is Document) return false;
    final siblings = _elementChildren(parent);
    return switch (kind) {
      _ChildKind.first => identical(siblings.first, element),
      _ChildKind.last => identical(siblings.last, element),
      _ChildKind.only => siblings.length == 1,
      _ChildKind.onlyOfType => siblings.where((e) => _normalName(e) == _normalName(element)).length == 1,
    };
  }
}

final class _EmptyEval extends _Evaluator {
  @override
  bool matches(_MatchContext context, Node root, Node element) {
    for (final child in element.nodes) {
      // 和 jsoup 一样：遇到第一个文本节点就按它是否空白下结论
      if (child is Text) return !_isScriptText(child) && child.data.codeUnits.every(_isJsoupWhitespace);
      if (child is! Comment && child is! DocumentType) return false;
    }
    return true;
  }
}

final class _IsRootEval extends _Evaluator {
  @override
  bool matches(_MatchContext context, Node root, Node element) {
    final target = root is Document ? _elementChildren(root).firstOrNull : root;
    return identical(element, target);
  }
}

final class _ContainsTextEval extends _Evaluator {
  _ContainsTextEval(String text, {required this.own}) : text = _normaliseWhitespace(text).toLowerCase();

  final String text;
  final bool own;

  @override
  bool matches(_MatchContext context, Node root, Node element) =>
      (own ? jsoupOwnText(element) : jsoupText(element)).toLowerCase().contains(text);
}

final class _ContainsWholeTextEval extends _Evaluator {
  _ContainsWholeTextEval(this.text, {required this.own});

  final String text;
  final bool own;

  @override
  bool matches(_MatchContext context, Node root, Node element) =>
      (own ? _wholeOwnText(element) : _wholeText(element)).contains(text);
}

final class _ContainsDataEval extends _Evaluator {
  _ContainsDataEval(String text) : text = text.toLowerCase();

  final String text;

  @override
  bool matches(_MatchContext context, Node root, Node element) => jsoupData(element).toLowerCase().contains(text);
}

enum _TextKind { text, ownText, wholeText, wholeOwnText }

final class _MatchesEval extends _Evaluator {
  _MatchesEval(this.regex, this.kind);

  final SourceRegex regex;
  final _TextKind kind;

  @override
  bool matches(_MatchContext context, Node root, Node element) {
    final text = switch (kind) {
      _TextKind.text => jsoupText(element),
      _TextKind.ownText => jsoupOwnText(element),
      _TextKind.wholeText => _wholeText(element),
      _TextKind.wholeOwnText => _wholeOwnText(element),
    };
    return regex.firstMatch(context.env, text) != null;
  }
}

final class _HasEval extends _Evaluator {
  _HasEval(this.evaluator);

  final _Evaluator evaluator;

  /// 只看后代，不看元素本身；子查询以这个元素为根。
  @override
  bool matches(_MatchContext context, Node root, Node element) {
    bool find(Node node) {
      if (evaluator.matches(context, element, node)) return true;
      return node.nodes.any((child) => child is Element && find(child));
    }

    return element.nodes.any((child) => child is Element && find(child));
  }
}

final class _NotEval extends _Evaluator {
  _NotEval(this.evaluator);

  final _Evaluator evaluator;

  @override
  bool matches(_MatchContext context, Node root, Node element) => !context.memo(evaluator, root, element);
}

/// 后代组合符：某个祖先（不超出 root）匹配。
final class _AncestorEval extends _Evaluator {
  _AncestorEval(this.evaluator);

  final _Evaluator evaluator;

  @override
  bool matches(_MatchContext context, Node root, Node element) {
    if (identical(root, element)) return false;
    var parent = _parent(element);
    while (parent != null) {
      if (context.memo(evaluator, root, parent)) return true;
      if (identical(parent, root)) break;
      parent = _parent(parent);
    }
    return false;
  }
}

/// `a > b > c`：从右往左，逐级要求父元素匹配。
final class _ImmediateParentRun extends _Evaluator {
  _ImmediateParentRun(_Evaluator first) : evaluators = [first];

  final List<_Evaluator> evaluators;

  @override
  bool matches(_MatchContext context, Node root, Node element) {
    Node? current = element;
    for (var i = evaluators.length - 1; i >= 0; i--) {
      if (current == null || !evaluators[i].matches(context, root, current)) return false;
      current = _parent(current);
    }
    return true;
  }
}

final class _PreviousSiblingEval extends _Evaluator {
  _PreviousSiblingEval(this.evaluator, {required this.immediate});

  final _Evaluator evaluator;
  final bool immediate;

  @override
  bool matches(_MatchContext context, Node root, Node element) {
    if (identical(root, element)) return false;
    final parent = _parent(element);
    if (parent == null) return false;
    final siblings = _elementChildren(parent);
    final index = context.elementSiblingIndex(element);
    if (immediate) return index > 0 && context.memo(evaluator, root, siblings[index - 1]);
    for (var i = 0; i < index; i++) {
      if (context.memo(evaluator, root, siblings[i])) return true;
    }
    return false;
  }
}

// ---------------------------------------------------------------- 解析

const List<String> _combinators = [',', '>', '+', '~', ' '];
const List<String> _attributeOps = ['=', '!=', '^=', r'$=', '*=', '~='];

final class _QueryParser {
  _QueryParser(this.query) : tq = _TokenQueue(query);

  final String query;
  final _TokenQueue tq;
  final List<_Evaluator> evals = [];

  _Evaluator parse() {
    tq.consumeWhitespace();
    if (tq.matchesAnyChar(_combinators)) {
      // 以组合符开头时，以起点元素为左侧
      evals.add(_RootEval());
      _combinator(tq.consume());
    } else {
      evals.add(_consumeEvaluator());
    }

    while (!tq.isEmpty) {
      final seenWhite = tq.consumeWhitespace();
      if (tq.matchesAnyChar(_combinators)) {
        _combinator(tq.consume());
      } else if (seenWhite) {
        _combinator(' ');
      } else {
        evals.add(_consumeEvaluator());
      }
    }
    return evals.length == 1 ? evals.single : _AndEval([...evals]);
  }

  void _combinator(String combinator) {
    tq.consumeWhitespace();
    final subQuery = _consumeSubQuery();
    final newEval = _QueryParser(subQuery.trim()).parse();

    _Evaluator rootEval;
    _Evaluator currentEval;
    var replaceRightMost = false;
    if (evals.length == 1) {
      rootEval = currentEval = evals.single;
      // 逗号的优先级最低：其它组合符作用在 Or 的最后一项上
      if (rootEval is _OrEval && combinator != ',') {
        currentEval = rootEval.evaluators.last;
        replaceRightMost = true;
      }
    } else {
      rootEval = currentEval = _AndEval([...evals]);
    }
    evals.clear();

    switch (combinator) {
      case '>':
        final run = currentEval is _ImmediateParentRun ? currentEval : _ImmediateParentRun(currentEval);
        run.evaluators.add(newEval);
        currentEval = run;
      case ' ':
        currentEval = _AndEval([_AncestorEval(currentEval), newEval]);
      case '+':
        currentEval = _AndEval([_PreviousSiblingEval(currentEval, immediate: true), newEval]);
      case '~':
        currentEval = _AndEval([_PreviousSiblingEval(currentEval, immediate: false), newEval]);
      case ',':
        final or = currentEval is _OrEval ? currentEval : _OrEval([currentEval]);
        or.evaluators.add(newEval);
        currentEval = or;
      default:
        throw FormatException('未知的组合符 $combinator', query);
    }

    if (replaceRightMost) {
      final or = rootEval as _OrEval;
      or.evaluators[or.evaluators.length - 1] = currentEval;
    } else {
      rootEval = currentEval;
    }
    evals.add(rootEval);
  }

  String _consumeSubQuery() {
    final sq = StringBuffer();
    while (!tq.isEmpty) {
      if (tq.matches('(')) {
        sq.write('(${tq.chompBalanced('(', ')')})');
      } else if (tq.matches('[')) {
        sq.write('[${tq.chompBalanced('[', ']')}]');
      } else if (tq.matchesAnyChar(_combinators)) {
        if (sq.isNotEmpty) break;
        tq.consume();
      } else {
        sq.write(tq.consume());
      }
    }
    return sq.toString();
  }

  _Evaluator _consumeEvaluator() {
    if (tq.matchChomp('#')) return _IdEval(_notEmpty(tq.consumeCssIdentifier()));
    if (tq.matchChomp('.')) return _ClassEval(_notEmpty(tq.consumeCssIdentifier()).trim());
    if (tq.matchesWord() || tq.matches('*|')) return _byTag();
    if (tq.matches('[')) return _byAttribute();
    if (tq.matchChomp('*')) return _AllEval();
    if (tq.matchChomp(':')) return _pseudo();
    throw FormatException('无法解析选择器：${tq.remainder}', query);
  }

  _Evaluator _byTag() {
    var tagName = _notEmpty(tq.consumeElementSelector().trim().toLowerCase());
    if (tagName.startsWith('*|')) {
      final plain = tagName.substring(2);
      return _OrEval([_TagEval(plain), _TagEndsWithEval(tagName.replaceAll('*|', ':'))]);
    }
    if (tagName.contains('|')) tagName = tagName.replaceAll('|', ':');
    return _TagEval(tagName);
  }

  _Evaluator _byAttribute() {
    final cq = _TokenQueue(tq.chompBalanced('[', ']'));
    final key = _notEmpty(cq.consumeToAny(_attributeOps));
    cq.consumeWhitespace();
    if (cq.isEmpty) {
      return key.startsWith('^') ? _AttributeStartingEval(_notEmpty(key.substring(1))) : _AttributeEval(key);
    }
    if (cq.matchChomp('=')) return _AttributeValueEval(key, cq.remainder, _ValueOp.equals);
    if (cq.matchChomp('!=')) return _AttributeValueEval(key, cq.remainder, _ValueOp.notEquals);
    if (cq.matchChomp('^=')) return _AttributeValueEval(key, cq.remainder, _ValueOp.starting);
    if (cq.matchChomp(r'$=')) return _AttributeValueEval(key, cq.remainder, _ValueOp.ending);
    if (cq.matchChomp('*=')) return _AttributeValueEval(key, cq.remainder, _ValueOp.containing);
    if (cq.matchChomp('~=')) return _AttributeMatchingEval(key, _regex(cq.remainder));
    throw FormatException('无法解析属性选择：${cq.remainder}', query);
  }

  _Evaluator _pseudo() {
    final pseudo = tq.consumeCssIdentifier();
    switch (pseudo) {
      case 'lt':
        return _IndexEval(_consumeIndex(), _IndexOp.lessThan);
      case 'gt':
        return _IndexEval(_consumeIndex(), _IndexOp.greaterThan);
      case 'eq':
        return _IndexEval(_consumeIndex(), _IndexOp.equals);
      case 'has':
        return _HasEval(_QueryParser(_notEmpty(_consumeParens()).trim()).parse());
      case 'contains' || 'containsOwn':
        return _ContainsTextEval(_notEmpty(_TokenQueue.unescape(_consumeParens())), own: pseudo == 'containsOwn');
      case 'containsWholeText' || 'containsWholeOwnText':
        final text = _notEmpty(_TokenQueue.unescape(_consumeParens()));
        return _ContainsWholeTextEval(text, own: pseudo == 'containsWholeOwnText');
      case 'containsData':
        return _ContainsDataEval(_notEmpty(_TokenQueue.unescape(_consumeParens())));
      case 'matches':
        return _MatchesEval(_regex(_notEmpty(_consumeParens())), _TextKind.text);
      case 'matchesOwn':
        return _MatchesEval(_regex(_notEmpty(_consumeParens())), _TextKind.ownText);
      case 'matchesWholeText':
        return _MatchesEval(_regex(_notEmpty(_consumeParens())), _TextKind.wholeText);
      case 'matchesWholeOwnText':
        return _MatchesEval(_regex(_notEmpty(_consumeParens())), _TextKind.wholeOwnText);
      case 'not':
        return _NotEval(_QueryParser(_notEmpty(_consumeParens()).trim()).parse());
      case 'nth-child':
        return _nth(_NthKind.child);
      case 'nth-last-child':
        return _nth(_NthKind.lastChild);
      case 'nth-of-type':
        return _nth(_NthKind.ofType);
      case 'nth-last-of-type':
        return _nth(_NthKind.lastOfType);
      case 'first-child':
        return _ChildEval(_ChildKind.first);
      case 'last-child':
        return _ChildEval(_ChildKind.last);
      case 'first-of-type':
        return _NthEval(0, 1, _NthKind.ofType);
      case 'last-of-type':
        return _NthEval(0, 1, _NthKind.lastOfType);
      case 'only-child':
        return _ChildEval(_ChildKind.only);
      case 'only-of-type':
        return _ChildEval(_ChildKind.onlyOfType);
      case 'empty':
        return _EmptyEval();
      case 'root':
        return _IsRootEval();
      default:
        throw FormatException('不支持的伪类 :$pseudo', query);
    }
  }

  static final RegExp _nthAb = RegExp(r'^(([+-])?(\d+)?)n(\s*([+-])?\s*\d+)?$', caseSensitive: false);
  static final RegExp _nthB = RegExp(r'^([+-])?(\d+)$');

  _Evaluator _nth(_NthKind kind) {
    final arg = _consumeParens().trim().toLowerCase();
    int a;
    int b;
    if (arg == 'odd') {
      (a, b) = (2, 1);
    } else if (arg == 'even') {
      (a, b) = (2, 0);
    } else if (_nthAb.firstMatch(arg) case final match?) {
      // 照 jsoup：没有系数时 a 为 1（`-n+3` 也是）；b 里带空格时 jsoup 解析失败，这里同样抛错
      a = match.group(3) != null ? int.parse(match.group(1)!.replaceFirst(RegExp(r'^\+'), '')) : 1;
      b = match.group(4) != null ? int.parse(match.group(4)!.replaceFirst(RegExp(r'^\+'), '')) : 0;
    } else if (_nthB.hasMatch(arg)) {
      (a, b) = (0, int.parse(arg.replaceFirst('+', '')));
    } else {
      throw FormatException('无法解析 nth 参数 $arg', query);
    }
    return _NthEval(a, b, kind);
  }

  String _consumeParens() => tq.chompBalanced('(', ')');

  int _consumeIndex() {
    final index = _consumeParens().trim();
    if (index.isEmpty || !index.codeUnits.every((c) => c >= 0x30 && c <= 0x39)) {
      throw FormatException('索引必须是数字：$index', query);
    }
    return int.parse(index);
  }

  SourceRegex _regex(String pattern) =>
      SourceRegex.tryCompile(pattern) ?? (throw FormatException('正则无法编译：$pattern', query));

  String _notEmpty(String value) => value.isEmpty ? throw FormatException('选择器缺少内容', query) : value;
}

/// jsoup 的 `TokenQueue`，只保留选择器解析用到的部分。`matches` 不区分大小写。
final class _TokenQueue {
  _TokenQueue(this.queue);

  final String queue;
  int pos = 0;

  bool get isEmpty => pos >= queue.length;

  String get remainder => queue.substring(pos);

  String consume() => queue[pos++];

  bool matches(String seq) =>
      queue.length - pos >= seq.length && queue.substring(pos, pos + seq.length).toLowerCase() == seq.toLowerCase();

  bool matchesAny(List<String> seqs) => seqs.any(matches);

  bool matchesAnyChar(List<String> chars) => !isEmpty && chars.contains(queue[pos]);

  bool matchChomp(String seq) {
    if (!matches(seq)) return false;
    pos += seq.length;
    return true;
  }

  /// Java `Character.isLetterOrDigit`。
  bool matchesWord() => !isEmpty && _isLetterOrDigit(queue.codeUnitAt(pos));

  bool consumeWhitespace() {
    var seen = false;
    while (!isEmpty && _isJsoupWhitespace(queue.codeUnitAt(pos))) {
      pos++;
      seen = true;
    }
    return seen;
  }

  String consumeToAny(List<String> seqs) {
    final start = pos;
    while (!isEmpty && !matchesAny(seqs)) {
      pos++;
    }
    return queue.substring(start, pos);
  }

  String consumeElementSelector() => _consumeEscapedIdentifier(const ['*|', '|', '_', '-']);

  String consumeCssIdentifier() => _consumeEscapedIdentifier(const ['-', '_']);

  String _consumeEscapedIdentifier(List<String> extra) {
    final start = pos;
    var escaped = false;
    while (!isEmpty) {
      if (queue[pos] == r'\' && queue.length - pos > 1) {
        escaped = true;
        pos += 2;
      } else if (matchesWord() || matchesAny(extra)) {
        pos++;
      } else {
        break;
      }
    }
    final consumed = queue.substring(start, pos);
    return escaped ? unescape(consumed) : consumed;
  }

  /// 取出成对括号里的内容，引号里的括号不计；括号不配对时抛出 [FormatException]。
  String chompBalanced(String open, String close) {
    var start = -1;
    var end = -1;
    var depth = 0;
    var last = '';
    var inSingleQuote = false;
    var inDoubleQuote = false;
    var inRegexQE = false;
    do {
      if (isEmpty) break;
      final c = consume();
      if (last != r'\') {
        if (c == "'" && c != open && !inDoubleQuote) {
          inSingleQuote = !inSingleQuote;
        } else if (c == '"' && c != open && !inSingleQuote) {
          inDoubleQuote = !inDoubleQuote;
        }
        if (inSingleQuote || inDoubleQuote || inRegexQE) {
          last = c;
          continue;
        }
        if (c == open) {
          depth++;
          if (start == -1) start = pos;
        } else if (c == close) {
          depth--;
        }
      } else if (c == 'Q') {
        inRegexQE = true;
      } else if (c == 'E') {
        inRegexQE = false;
      }
      if (depth > 0 && last.isNotEmpty) end = pos;
      last = c;
    } while (depth > 0);
    final out = end >= 0 ? queue.substring(start, end) : '';
    if (depth > 0) throw FormatException('括号不配对：$out', queue);
    return out;
  }

  static String unescape(String text) {
    final out = StringBuffer();
    var last = '';
    for (var i = 0; i < text.length; i++) {
      var c = text[i];
      if (c == r'\') {
        if (last == r'\') {
          out.write(c);
          c = '';
        }
      } else {
        out.write(c);
      }
      last = c;
    }
    return out.toString();
  }
}

// ---------------------------------------------------------------- 文本

/// `Element.wholeText()`：原样的文本，`br` 转成换行。
String _wholeText(Node node) {
  final out = StringBuffer();
  void visit(Node current) {
    if (current is Text && !_isScriptText(current)) out.write(current.data);
    if (current is Element && current.localName == 'br') out.write('\n');
    current.nodes.forEach(visit);
  }

  node.nodes.forEach(visit);
  return out.toString();
}

/// `Element.wholeOwnText()`：直接子文本原样连接，`br` 转成换行。
String _wholeOwnText(Node node) {
  final out = StringBuffer();
  for (final child in node.nodes) {
    if (child is Text && !_isScriptText(child)) out.write(child.data);
    if (child is Element && child.localName == 'br') out.write('\n');
  }
  return out.toString();
}

bool _isScriptText(Text text) {
  final parent = text.parentNode;
  return parent is Element && (parent.localName == 'script' || parent.localName == 'style');
}

String _normaliseWhitespace(String text) {
  final out = StringBuffer();
  var lastWasWhite = false;
  for (final c in text.runes) {
    if (_isJsoupWhitespace(c) || c == 0xA0) {
      if (lastWasWhite) continue;
      out.write(' ');
      lastWasWhite = true;
    } else if (c != 0x200B && c != 0xAD) {
      out.writeCharCode(c);
      lastWasWhite = false;
    }
  }
  return out.toString();
}

bool _isJsoupWhitespace(int c) => c == 0x20 || c == 0x9 || c == 0xA || c == 0xC || c == 0xD;

/// Java `Character.isWhitespace` 里常见的部分，用于切分 class 属性。
final RegExp _javaWhitespace = RegExp(r'[\s\x1C-\x1F]+');

/// Java `Character.isLetterOrDigit` 的近似：ASCII 字母数字，以及 Unicode 字母和数字。
bool _isLetterOrDigit(int c) {
  if (c < 0x80) return (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
  return _unicodeLetterOrDigit.hasMatch(String.fromCharCode(c));
}

final RegExp _unicodeLetterOrDigit = RegExp(r'[\p{L}\p{Nd}]', unicode: true);
