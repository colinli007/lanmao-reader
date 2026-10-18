/// Jayway JsonPath（MD3 用的 json-path 3.0.0，默认配置）的子集。
///
/// 和 RFC 9535 不同的地方都按 Jayway 处理：
/// - 不以 `$` 或 `@` 开头的路径前面补 `$.`；
/// - 属性名可以含 `-` 等字符，到 `.`、`[`、`(` 为止；
/// - 确定路径（只含单个属性和单个下标）返回单个值，取不到时抛出 [JsonPathNotFound]；
///   不确定路径（含 `*`、`..`、过滤、切片、多选）返回值的列表，取不到的部分跳过。
///
/// 支持：`.name`、`['name']`、`[n]`（可为负）、`[a,b]`、`[start:end]`、`*`、`..`、`[?(过滤)]`；
/// 过滤里支持 `@` / `$` 路径、字符串、数字、布尔、null，`==`、`!=`、`<`、`<=`、`>`、`>=`、`&&`、`||`、`!` 和括号。
/// 其余写法（函数、`=~` 等）抛出 [FormatException]。
library;

/// 路径取不到值（Jayway 的 PathNotFoundException）。
final class JsonPathNotFound implements Exception {
  const JsonPathNotFound(this.path);

  final String path;

  @override
  String toString() => 'JsonPathNotFound: $path';
}

final class JsonPath {
  JsonPath._(this.path, this._tokens);

  /// 语法不支持时抛出 [FormatException]。
  factory JsonPath.parse(String path) {
    var text = path.trim();
    if (!text.startsWith(r'$') && !text.startsWith('@')) text = '\$.$text';
    return JsonPath._(path, _PathParser(text).parse());
  }

  final String path;
  final List<_Token> _tokens;

  /// 只含单个属性和单个下标。
  bool get isDefinite => _tokens.every((token) => token.isDefinite);

  /// Jayway 的 `read`：确定路径返回单个值，不确定路径返回列表。
  Object? read(Object? document) {
    final results = evaluate(document, document);
    if (isDefinite) {
      if (results.isEmpty) throw JsonPathNotFound(path);
      return results.single;
    }
    return results;
  }

  /// 全部匹配的值。[root] 是 `$` 指向的文档。
  List<Object?> evaluate(Object? current, Object? root) {
    var nodes = <Object?>[current];
    for (final token in _tokens) {
      nodes = [for (final node in nodes) ...token.apply(node, root)];
    }
    return nodes;
  }
}

sealed class _Token {
  bool get isDefinite;

  List<Object?> apply(Object? node, Object? root);
}

final class _PropertyToken extends _Token {
  _PropertyToken(this.names);

  final List<String> names;

  // 多个属性时返回一个合并的对象，Jayway 也算确定路径
  @override
  bool get isDefinite => true;

  @override
  List<Object?> apply(Object? node, Object? root) {
    if (node is! Map) return const [];
    if (names.length == 1) return node.containsKey(names.single) ? [node[names.single]] : const [];
    // 多个属性：Jayway 返回只含这些键的对象
    return [
      {
        for (final name in names)
          if (node.containsKey(name)) name: node[name],
      },
    ];
  }
}

final class _WildcardToken extends _Token {
  @override
  bool get isDefinite => false;

  @override
  List<Object?> apply(Object? node, Object? root) => switch (node) {
    Map() => node.values.toList(),
    List() => node,
    _ => const [],
  };
}

final class _IndexToken extends _Token {
  _IndexToken(this.indexes);

  final List<int> indexes;

  @override
  bool get isDefinite => indexes.length == 1;

  @override
  List<Object?> apply(Object? node, Object? root) {
    if (node is! List) return const [];
    return [
      for (final index in indexes)
        if ((index < 0 ? node.length + index : index) case final i when i >= 0 && i < node.length) node[i],
    ];
  }
}

final class _SliceToken extends _Token {
  _SliceToken(this.from, this.to);

  final int? from;
  final int? to;

  @override
  bool get isDefinite => false;

  @override
  List<Object?> apply(Object? node, Object? root) {
    if (node is! List) return const [];
    final length = node.length;
    var start = from ?? 0;
    var end = to ?? length;
    if (start < 0) start = (length + start).clamp(0, length);
    if (end < 0) end = (length + end).clamp(0, length);
    start = start.clamp(0, length);
    end = end.clamp(0, length);
    return start < end ? node.sublist(start, end) : const [];
  }
}

/// `..`：对自己和全部后代容器（先序）应用下一个记号。
final class _ScanToken extends _Token {
  _ScanToken(this.next);

  final _Token next;

  @override
  bool get isDefinite => false;

  @override
  List<Object?> apply(Object? node, Object? root) {
    final results = <Object?>[];
    void walk(Object? current) {
      if (current is! Map && current is! List) return;
      results.addAll(next.apply(current, root));
      final children = current is Map ? current.values : current as List;
      children.forEach(walk);
    }

    walk(node);
    return results;
  }
}

final class _FilterToken extends _Token {
  _FilterToken(this.filter);

  final _Expr filter;

  @override
  bool get isDefinite => false;

  /// 数组：保留满足条件的元素；对象：满足条件时保留对象本身（Jayway 的行为）。
  @override
  List<Object?> apply(Object? node, Object? root) => switch (node) {
    List() => [
      for (final item in node)
        if (filter.test(item, root)) item,
    ],
    Map() when filter.test(node, root) => [node],
    _ => const [],
  };
}

// ---------------------------------------------------------------- 过滤表达式

sealed class _Expr {
  bool test(Object? current, Object? root);
}

final class _OrExpr extends _Expr {
  _OrExpr(this.left, this.right);

  final _Expr left;
  final _Expr right;

  @override
  bool test(Object? current, Object? root) => left.test(current, root) || right.test(current, root);
}

final class _AndExpr extends _Expr {
  _AndExpr(this.left, this.right);

  final _Expr left;
  final _Expr right;

  @override
  bool test(Object? current, Object? root) => left.test(current, root) && right.test(current, root);
}

final class _NotExpr extends _Expr {
  _NotExpr(this.inner);

  final _Expr inner;

  @override
  bool test(Object? current, Object? root) => !inner.test(current, root);
}

/// 单独一个路径：路径存在即为真；单独一个字面量：按真值判断。
final class _ExistsExpr extends _Expr {
  _ExistsExpr(this.operand);

  final _Operand operand;

  @override
  bool test(Object? current, Object? root) {
    final value = operand.resolve(current, root);
    if (operand is _PathOperand) return value != _missing;
    return value == true;
  }
}

final class _CompareExpr extends _Expr {
  _CompareExpr(this.left, this.op, this.right);

  final _Operand left;
  final String op;
  final _Operand right;

  @override
  bool test(Object? current, Object? root) {
    final a = left.resolve(current, root);
    final b = right.resolve(current, root);
    if (op == '!=') return !_equals(a, b);
    if (op == '==') return _equals(a, b);
    if (a is num && b is num) {
      return switch (op) {
        '<' => a < b,
        '<=' => a <= b,
        '>' => a > b,
        _ => a >= b,
      };
    }
    if (a is String && b is String) {
      final order = a.compareTo(b);
      return switch (op) {
        '<' => order < 0,
        '<=' => order <= 0,
        '>' => order > 0,
        _ => order >= 0,
      };
    }
    return false;
  }

  static bool _equals(Object? a, Object? b) {
    if (identical(a, _missing) || identical(b, _missing)) return false;
    if (a is num && b is num) return a == b;
    return a == b;
  }
}

/// 路径取不到值。
const Object _missing = Object();

sealed class _Operand {
  Object? resolve(Object? current, Object? root);
}

final class _LiteralOperand extends _Operand {
  _LiteralOperand(this.value);

  final Object? value;

  @override
  Object? resolve(Object? current, Object? root) => value;
}

final class _PathOperand extends _Operand {
  _PathOperand(this.fromRoot, this.tokens);

  final bool fromRoot;
  final List<_Token> tokens;

  @override
  Object? resolve(Object? current, Object? root) {
    var nodes = <Object?>[fromRoot ? root : current];
    for (final token in tokens) {
      nodes = [for (final node in nodes) ...token.apply(node, root)];
    }
    if (nodes.isEmpty) return _missing;
    return tokens.every((token) => token.isDefinite) ? nodes.single : nodes;
  }
}

// ---------------------------------------------------------------- 解析

final class _PathParser {
  _PathParser(this.text);

  final String text;
  int pos = 0;

  bool get atEnd => pos >= text.length;

  Never fail(String message) => throw FormatException(message, text, pos);

  /// 整条路径，以 `$` 或 `@` 开头。
  List<_Token> parse() {
    pos = 1;
    final tokens = _readTokens(stopAt: null);
    if (!atEnd) fail('无法解析的路径');
    return tokens;
  }

  /// 读到字符串末尾，或者遇到 [stopAt] 里的字符（过滤表达式里的路径）。
  List<_Token> _readTokens({required Set<String>? stopAt}) {
    final tokens = <_Token>[];
    while (!atEnd) {
      final char = text[pos];
      if (stopAt != null && (stopAt.contains(char) || char == ' ')) break;
      if (text.startsWith('..', pos)) {
        pos += 2;
        if (atEnd) fail('路径不能以 .. 结尾');
        final next = text[pos] == '[' ? _readBracket() : _readDotted();
        tokens.add(_ScanToken(next));
      } else if (char == '.') {
        pos++;
        if (atEnd) fail('路径不能以 . 结尾');
        // Jayway：`.` 后面紧跟 `[` 时按方括号读（`$.[*]` 等于 `$[*]`）
        tokens.add(text[pos] == '[' ? _readBracket() : _readDotted());
      } else if (char == '[') {
        tokens.add(_readBracket());
      } else {
        fail('无法解析的路径');
      }
    }
    return tokens;
  }

  /// `.` 之后：`*` 或属性名（到 `.`、`[`、`(` 为止，不能含空格）。
  _Token _readDotted() {
    if (text[pos] == '*') {
      pos++;
      return _WildcardToken();
    }
    final start = pos;
    while (!atEnd && !'.[()'.contains(text[pos]) && text[pos] != ' ' && !_inFilterEnd()) {
      pos++;
    }
    if (!atEnd && text[pos] == '(') fail('不支持路径函数');
    if (pos == start) fail('缺少属性名');
    return _PropertyToken([text.substring(start, pos)]);
  }

  // 过滤表达式里的路径遇到比较运算符、逻辑运算符或右括号时结束
  bool _inFilterEnd() => _filterDepth > 0 && '=!<>&|)'.contains(text[pos]);
  int _filterDepth = 0;

  _Token _readBracket() {
    pos++; // [
    _skipSpace();
    if (atEnd) fail('方括号没有结束');
    final _Token token;
    if (text[pos] == '*') {
      pos++;
      token = _WildcardToken();
    } else if (text[pos] == '?') {
      pos++;
      _skipSpace();
      if (atEnd || text[pos] != '(') fail('过滤表达式缺少括号');
      pos++;
      _filterDepth++;
      final expr = _readOr();
      _filterDepth--;
      _skipSpace();
      if (atEnd || text[pos] != ')') fail('过滤表达式没有结束');
      pos++;
      token = _FilterToken(expr);
    } else if (text[pos] == "'" || text[pos] == '"') {
      final names = <String>[_readQuoted()];
      _skipSpace();
      while (!atEnd && text[pos] == ',') {
        pos++;
        _skipSpace();
        names.add(_readQuoted());
        _skipSpace();
      }
      token = _PropertyToken(names);
    } else {
      final end = text.indexOf(']', pos);
      if (end < 0) fail('方括号没有结束');
      final content = text.substring(pos, end).replaceAll(' ', '');
      pos = end;
      token = content.contains(':') ? _slice(content) : _indexes(content);
    }
    _skipSpace();
    if (atEnd || text[pos] != ']') fail('方括号没有结束');
    pos++;
    return token;
  }

  _Token _slice(String content) {
    final parts = content.split(':');
    if (parts.length > 2) fail('不支持带步长的切片');
    int? bound(String part) => part.isEmpty ? null : int.tryParse(part) ?? fail('切片下标不是整数');
    return _SliceToken(bound(parts[0]), bound(parts[1]));
  }

  _Token _indexes(String content) =>
      _IndexToken([for (final part in content.split(',')) int.tryParse(part) ?? fail('下标不是整数')]);

  String _readQuoted() {
    final quote = text[pos++];
    final out = StringBuffer();
    while (!atEnd && text[pos] != quote) {
      if (text[pos] == r'\' && pos + 1 < text.length) pos++;
      out.write(text[pos++]);
    }
    if (atEnd) fail('字符串没有结束');
    pos++;
    return out.toString();
  }

  _Expr _readOr() {
    var left = _readAnd();
    while (_take('||')) {
      left = _OrExpr(left, _readAnd());
    }
    return left;
  }

  _Expr _readAnd() {
    var left = _readUnary();
    while (_take('&&')) {
      left = _AndExpr(left, _readUnary());
    }
    return left;
  }

  _Expr _readUnary() {
    _skipSpace();
    if (!text.startsWith('!=', pos) && _take('!')) return _NotExpr(_readUnary());
    if (!atEnd && text[pos] == '(') {
      pos++;
      final inner = _readOr();
      if (!_take(')')) fail('括号不配对');
      return inner;
    }
    final left = _readOperand();
    _skipSpace();
    for (final op in const ['==', '!=', '<=', '>=', '<', '>']) {
      if (_take(op)) return _CompareExpr(left, op, _readOperand());
    }
    if (text.startsWith('=~', pos) || text.startsWith(' in ', pos)) fail('不支持的过滤运算符');
    return _ExistsExpr(left);
  }

  _Operand _readOperand() {
    _skipSpace();
    if (atEnd) fail('缺少操作数');
    final char = text[pos];
    if (char == '@' || char == r'$') {
      pos++;
      return _PathOperand(char == r'$', _readTokens(stopAt: const {'=', '!', '<', '>', '&', '|', ')'}));
    }
    if (char == "'" || char == '"') return _LiteralOperand(_readQuoted());
    final match = _literal.matchAsPrefix(text, pos) ?? fail('无法解析的操作数');
    pos = match.end;
    final literal = match.group(0)!;
    return _LiteralOperand(switch (literal) {
      'true' => true,
      'false' => false,
      'null' => null,
      _ => num.parse(literal),
    });
  }

  static final RegExp _literal = RegExp(r'true|false|null|-?\d+(\.\d+)?([eE][+-]?\d+)?');

  bool _take(String token) {
    _skipSpace();
    if (!text.startsWith(token, pos)) return false;
    pos += token.length;
    return true;
  }

  void _skipSpace() {
    while (!atEnd && text[pos] == ' ') {
      pos++;
    }
  }
}
