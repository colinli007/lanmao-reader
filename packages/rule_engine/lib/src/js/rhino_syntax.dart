/// Rhino 认、QuickJS 不认的语法，执行前改写成等价的标准写法（source-js「Rhino 专有写法」，add-rhino-compat 设计 D4）。
///
/// 目前只有一种：`=>` 前面紧挨着的数组字面量。Rhino 的 `Parser.arrowFunctionParams` 把它当成解构参数
/// （`[a,b]=>a+b` 等于 `([a,b])=>a+b`），QuickJS 按标准要求加括号。
library;

/// 改写后的代码；没有要改写的地方时原样返回（先用正则检查，绝大多数代码不扫描）。
String rhinoCompatible(String code) => _candidate.hasMatch(code) ? _ArrowParams(code).rewrite() : code;

final RegExp _candidate = RegExp(r'\]\s*=>');

/// 逐字扫描，跳过字符串、模板字符串、注释和正则字面量，找出出现在表达式开头、配对的 `]` 后面紧跟 `=>` 的 `[`。
final class _ArrowParams {
  _ArrowParams(this.code);

  final String code;
  int pos = 0;

  /// 下一个记号是否在表达式开头：这时 `/` 是正则，`[` 是数组字面量；否则 `/` 是除号，`[` 是下标访问。
  bool exprStart = true;

  /// 未配对的 `[`：在表达式开头的记下位置，下标访问记 -1。
  final List<int> brackets = [];

  /// 未配对的 `{`：模板字符串里的 `${` 记 true，配对的 `}` 之后回到模板字符串。
  final List<bool> braces = [];

  /// 要加括号的数组字面量：`[` 的位置和 `]` 之后的位置。
  final List<(int, int)> wraps = [];

  String rewrite() {
    while (pos < code.length) {
      _next();
    }
    if (wraps.isEmpty) return code;
    final out = StringBuffer();
    var last = 0;
    final inserts = [for (final (open, close) in wraps) ...[(open, '('), (close, ')')]]..sort((a, b) => a.$1.compareTo(b.$1));
    for (final (at, text) in inserts) {
      out
        ..write(code.substring(last, at))
        ..write(text);
      last = at;
    }
    out.write(code.substring(last));
    return out.toString();
  }

  void _next() {
    final c = code[pos];
    if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
      pos++;
    } else if (code.startsWith('//', pos)) {
      final end = code.indexOf('\n', pos);
      pos = end < 0 ? code.length : end;
    } else if (code.startsWith('/*', pos)) {
      final end = code.indexOf('*/', pos + 2);
      pos = end < 0 ? code.length : end + 2;
    } else if (c == '"' || c == "'") {
      _skipString(c);
      exprStart = false;
    } else if (c == '`') {
      pos++;
      _template();
    } else if (c == '/') {
      if (exprStart) {
        _skipRegex();
        exprStart = false;
      } else {
        pos++;
        exprStart = true;
      }
    } else if (_isWordChar(c)) {
      final start = pos;
      while (pos < code.length && _isWordChar(code[pos])) {
        pos++;
      }
      final word = code.substring(start, pos);
      // 数字和普通标识符之后是除号、下标；关键字之后是新的表达式
      exprStart = _keywords.contains(word);
    } else if (c == '[') {
      brackets.add(exprStart ? pos : -1);
      pos++;
      exprStart = true;
    } else if (c == ']') {
      final open = brackets.isEmpty ? -1 : brackets.removeLast();
      pos++;
      if (open >= 0 && code.startsWith('=>', _skipSpaces(pos))) wraps.add((open, pos));
      exprStart = false;
    } else if (c == '{') {
      braces.add(false);
      pos++;
      exprStart = true;
    } else if (c == '}') {
      pos++;
      if (braces.isNotEmpty && braces.removeLast()) {
        _template();
      } else {
        exprStart = true;
      }
    } else if (c == ')') {
      pos++;
      exprStart = false;
    } else {
      // 运算符、`(`、`,`、`;`、`:`、`?` 等之后是新的表达式
      pos++;
      exprStart = true;
    }
  }

  int _skipSpaces(int from) {
    var at = from;
    while (at < code.length && ' \t\r\n'.contains(code[at])) {
      at++;
    }
    return at;
  }

  void _skipString(String quote) {
    pos++;
    while (pos < code.length) {
      final c = code[pos];
      if (c == r'\') {
        pos += 2;
      } else if (c == quote || c == '\n') {
        pos++;
        return;
      } else {
        pos++;
      }
    }
  }

  /// 模板字符串的一段：到结尾的反引号，或者到 `${`（之后按代码扫描，配对的 `}` 再回到这里）。
  void _template() {
    while (pos < code.length) {
      final c = code[pos];
      if (c == r'\') {
        pos += 2;
      } else if (c == '`') {
        pos++;
        exprStart = false;
        return;
      } else if (code.startsWith(r'${', pos)) {
        pos += 2;
        braces.add(true);
        exprStart = true;
        return;
      } else {
        pos++;
      }
    }
  }

  void _skipRegex() {
    pos++;
    var inClass = false;
    while (pos < code.length) {
      final c = code[pos];
      if (c == r'\') {
        pos += 2;
        continue;
      }
      pos++;
      if (c == '\n') return;
      if (c == '[') {
        inClass = true;
      } else if (c == ']') {
        inClass = false;
      } else if (c == '/' && !inClass) {
        break;
      }
    }
    while (pos < code.length && _isWordChar(code[pos])) {
      pos++;
    }
  }

  static bool _isWordChar(String c) {
    final unit = c.codeUnitAt(0);
    return (unit >= 0x30 && unit <= 0x39) ||
        (unit >= 0x41 && unit <= 0x5a) ||
        (unit >= 0x61 && unit <= 0x7a) ||
        c == '_' ||
        c == r'$' ||
        unit > 0x7f;
  }

  /// 之后是新表达式的关键字（`return [a]` 是数组字面量，`return /x/` 是正则）。
  static const Set<String> _keywords = {
    'return', 'typeof', 'instanceof', 'in', 'of', 'new', 'delete', 'void', 'throw', 'case', 'do', 'else', 'yield', 'await', //
  };
}
