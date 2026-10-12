import '../core/errors.dart';

/// MD3 的 `RuleAnalyzer`：切分 `&&`、`||`、`%%`、`@`，跳过 `[]`、`()` 和引号里的分隔符，以及替换内嵌规则。
///
/// 照 MD3 源码逐行移植，切分结果（包括边界上的怪异行为）和 MD3 一致。
/// [code] 为真时（JSONPath、JS）按代码规则配平：引号里的 `\` 也转义，只有 `[]` 计深度。
final class RuleSplitter {
  RuleSplitter(this._queue, {bool code = false}) : _code = code;

  final String _queue;
  final bool _code;

  /// 当前处理到的位置。
  int _pos = 0;

  /// 当前字段的开始。
  int _start = 0;

  /// 当前规则的开始。
  int _startX = 0;

  List<String> _rule = [];

  /// 分隔符的长度。
  int _step = 0;

  /// 实际用来切分的分隔符，由第一个出现的分隔符决定。
  String elementsType = '';

  /// 去掉规则前面的 `@` 和空白（码值小于 `!` 的字符）。
  void trim() {
    if (_pos < _queue.length && _isTrimmable(_queue.codeUnitAt(_pos))) {
      _pos++;
      while (_pos < _queue.length && _isTrimmable(_queue.codeUnitAt(_pos))) {
        _pos++;
      }
      _start = _pos;
      _startX = _pos;
    }
  }

  static bool _isTrimmable(int c) => c == 0x40 || c < 0x21;

  /// 位置归零，复用切分器。
  void resetPos() {
    _pos = 0;
    _startX = 0;
  }

  bool _consumeTo(String seq) {
    _start = _pos;
    final offset = _queue.indexOf(seq, _pos);
    if (offset == -1) return false;
    _pos = offset;
    return true;
  }

  bool _consumeToAny(List<String> seqs) {
    var pos = _pos;
    while (pos != _queue.length) {
      for (final s in seqs) {
        if (_queue.startsWith(s, pos)) {
          _step = s.length;
          _pos = pos;
          return true;
        }
      }
      pos++;
    }
    return false;
  }

  int _findToAny(String a, String b) {
    for (var pos = _pos; pos < _queue.length; pos++) {
      final c = _queue[pos];
      if (c == a || c == b) return pos;
    }
    return -1;
  }

  /// 代码平衡组：引号外只有 `[]` 计深度，`[]` 之外的 [open]/[close] 另外计深度；`\` 总是转义下一个字符。
  bool _chompCodeBalanced(String open, String close) {
    var pos = _pos;
    var depth = 0;
    var otherDepth = 0;
    var inSingleQuote = false;
    var inDoubleQuote = false;
    do {
      if (pos == _queue.length) break;
      final c = _queue[pos++];
      if (c != r'\') {
        if (c == "'" && !inDoubleQuote) {
          inSingleQuote = !inSingleQuote;
        } else if (c == '"' && !inSingleQuote) {
          inDoubleQuote = !inDoubleQuote;
        }
        if (inSingleQuote || inDoubleQuote) continue;
        if (c == '[') {
          depth++;
        } else if (c == ']') {
          depth--;
        } else if (depth == 0) {
          if (c == open) {
            otherDepth++;
          } else if (c == close) {
            otherDepth--;
          }
        }
      } else {
        pos++;
      }
    } while (depth > 0 || otherDepth > 0);
    if (depth > 0 || otherDepth > 0) return false;
    _pos = pos;
    return true;
  }

  /// 规则平衡组：引号里的 `\` 不转义，引号外的 `\` 转义下一个字符。
  bool _chompRuleBalanced(String open, String close) {
    var pos = _pos;
    var depth = 0;
    var inSingleQuote = false;
    var inDoubleQuote = false;
    do {
      if (pos == _queue.length) break;
      final c = _queue[pos++];
      if (c == "'" && !inDoubleQuote) {
        inSingleQuote = !inSingleQuote;
      } else if (c == '"' && !inSingleQuote) {
        inDoubleQuote = !inDoubleQuote;
      }
      if (inSingleQuote || inDoubleQuote) {
        continue;
      } else if (c == r'\') {
        pos++;
        continue;
      }
      if (c == open) {
        depth++;
      } else if (c == close) {
        depth--;
      }
    } while (depth > 0);
    if (depth > 0) return false;
    _pos = pos;
    return true;
  }

  bool _chompBalanced(String open, String close) =>
      _code ? _chompCodeBalanced(open, close) : _chompRuleBalanced(open, close);

  /// 按 [split] 里第一个出现的分隔符切分，`[]`、`()` 里的分隔符跳过。
  /// 括号不配对时抛出 [RuleException]（MD3 抛 `Error`）。
  List<String> splitRule(List<String> split) {
    while (true) {
      if (split.length == 1) {
        elementsType = split.single;
        if (!_consumeTo(elementsType)) {
          _rule.add(_queue.substring(_startX));
          return _rule;
        }
        _step = elementsType.length;
        return _splitRuleNext();
      } else if (!_consumeToAny(split)) {
        _rule.add(_queue.substring(_startX));
        return _rule;
      }

      final end = _pos;
      _pos = _start;
      do {
        final st = _findToAny('[', '(');
        if (st == -1) {
          _rule = [_queue.substring(_startX, end)];
          elementsType = _queue.substring(end, end + _step);
          _pos = end + _step;
          while (_consumeTo(elementsType)) {
            _rule.add(_queue.substring(_start, _pos));
            _pos += _step;
          }
          _rule.add(_queue.substring(_pos));
          return _rule;
        }
        if (st > end) {
          _rule = [_queue.substring(_startX, end)];
          elementsType = _queue.substring(end, end + _step);
          _pos = end + _step;
          while (_consumeTo(elementsType) && _pos < st) {
            _rule.add(_queue.substring(_start, _pos));
            _pos += _step;
          }
          if (_pos > st) {
            _startX = _start;
            return _splitRuleNext();
          }
          _rule.add(_queue.substring(_pos));
          return _rule;
        }
        _pos = st;
        _chompOrFail();
      } while (end > _pos);
      _start = _pos;
    }
  }

  /// 二段匹配：分隔符已经确定为 [elementsType]。
  List<String> _splitRuleNext() {
    while (true) {
      final end = _pos;
      _pos = _start;
      do {
        final st = _findToAny('[', '(');
        if (st == -1) {
          _rule.add(_queue.substring(_startX, end));
          _pos = end + _step;
          while (_consumeTo(elementsType)) {
            _rule.add(_queue.substring(_start, _pos));
            _pos += _step;
          }
          _rule.add(_queue.substring(_pos));
          return _rule;
        }
        if (st > end) {
          _rule.add(_queue.substring(_startX, end));
          _pos = end + _step;
          while (_consumeTo(elementsType) && _pos < st) {
            _rule.add(_queue.substring(_start, _pos));
            _pos += _step;
          }
          if (_pos > st) {
            _startX = _start;
            continue;
          }
          _rule.add(_queue.substring(_pos));
          return _rule;
        }
        _pos = st;
        _chompOrFail();
      } while (end > _pos);
      _start = _pos;
      if (!_consumeTo(elementsType)) {
        _rule.add(_queue.substring(_startX));
        return _rule;
      }
    }
  }

  void _chompOrFail() {
    final open = _queue[_pos];
    if (!_chompBalanced(open, open == '[' ? ']' : ')')) {
      throw RuleException('${_queue.substring(0, _start)}后未平衡');
    }
  }

  /// 替换 [inner]（如 `{$.`）开头的内嵌规则：配平 `{}`，取出去掉首尾各一个字符的内容交给 [evaluate]，
  /// 结果非空时替换。一个都没替换时返回空串。
  String innerRule(String inner, String? Function(String rule) evaluate) {
    final out = StringBuffer();
    while (_consumeTo(inner)) {
      final posPre = _pos;
      if (_chompCodeBalanced('{', '}')) {
        final value = evaluate(_queue.substring(posPre + 1, _pos - 1));
        if (value != null && value.isNotEmpty) {
          out.write(_queue.substring(_startX, posPre) + value);
          _startX = _pos;
          continue;
        }
      }
      _pos += inner.length;
    }
    if (_startX == 0) return '';
    out.write(_queue.substring(_startX));
    return out.toString();
  }

  /// 替换 [startStr] 和 [endStr] 之间的内容（不配平，取下一个 [endStr]）。一个都没替换时返回原文。
  String innerRuleBetween(String startStr, String endStr, String Function(String inner) evaluate) {
    final out = StringBuffer();
    while (_consumeTo(startStr)) {
      _pos += startStr.length;
      final posPre = _pos;
      if (_consumeTo(endStr)) {
        final value = evaluate(_queue.substring(posPre, _pos));
        out.write(_queue.substring(_startX, posPre - startStr.length) + value);
        _pos += endStr.length;
        _startX = _pos;
      }
    }
    if (_startX == 0) return _queue;
    out.write(_queue.substring(_startX));
    return out.toString();
  }
}
