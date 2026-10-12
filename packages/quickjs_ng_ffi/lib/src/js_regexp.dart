part of '../quickjs_ng_ffi.dart';

// libregexp.h 里的 LRE_FLAG_*
const int _flagIgnoreCase = 1 << 1;
const int _flagMultiLine = 1 << 2;
const int _flagDotAll = 1 << 3;
const int _flagUnicode = 1 << 4;

/// 用 quickjs-ng 的 libregexp 执行的正则，语法同 JS `RegExp`。
///
/// 和 Dart [RegExp] 的区别是匹配可以被外部中止信号打断：书源提供的正则可能灾难性回溯，
/// 中止后匹配抛出 [JsException]（消息含 `interrupted`），引擎和这个正则都还能继续用。
///
/// 正则属于创建它的 [JsEngine]，只能在同一个 isolate 里使用；引擎释放时一并释放。
class JsRegExp {
  /// 正则无法编译时抛出 [FormatException]，消息是 libregexp 给出的原因。
  factory JsRegExp(
    JsEngine engine,
    String pattern, {
    bool ignoreCase = false,
    bool multiLine = false,
    bool dotAll = false,
    bool unicode = false,
  }) {
    engine._checkAlive();
    final flags =
        (ignoreCase ? _flagIgnoreCase : 0) |
        (multiLine ? _flagMultiLine : 0) |
        (dotAll ? _flagDotAll : 0) |
        (unicode ? _flagUnicode : 0);
    return using((arena) {
      final captureCount = arena<Int32>();
      final groupNames = arena<Pointer<Char>>();
      final error = arena<Pointer<Char>>();
      final bytecode = _bindings.qjs_regexp_compile(
        engine._engine,
        _encodePattern(pattern, unicode: unicode, allocator: arena).cast(),
        flags,
        captureCount,
        groupNames,
        error,
      );
      if (bytecode == nullptr) {
        final reason = _takeString(error.value) ?? 'unknown error';
        throw FormatException('正则无法编译：$reason', pattern);
      }
      final names = _takeString(groupNames.value)?.split(',');
      final regExp = JsRegExp._(
        engine,
        bytecode,
        pattern,
        captureCount.value - 1,
        names?.map((name) => name.isEmpty ? null : name).toList(),
        unicode,
      );
      engine._regExps.add(regExp);
      return regExp;
    });
  }

  JsRegExp._(this._engine, this._bytecode, this.pattern, this.groupCount, this._groupNames, this._unicode);

  final JsEngine _engine;
  Pointer<Uint8> _bytecode;
  final String pattern;

  /// 分组数，不含第 0 组。
  final int groupCount;

  /// 第 i 组的组名在下标 i - 1 处；没有命名分组时为 null。
  final List<String?>? _groupNames;
  final bool _unicode;

  /// 命名分组 [name] 的序号，没有这个组名时为 null。
  int? groupIndex(String name) {
    final index = _groupNames?.indexOf(name) ?? -1;
    return index < 0 ? null : index + 1;
  }

  /// 从 [start] 开始查找第一个匹配。
  JsRegExpMatch? firstMatch(String input, {int start = 0, Pointer<Int32>? abortSignal}) {
    return _withInput(input, (buffer, captures) => _exec(input, buffer, start, abortSignal, captures));
  }

  /// 从 [start] 开始查找全部不重叠的匹配。输入只复制到原生内存一次。
  List<JsRegExpMatch> allMatches(String input, {int start = 0, Pointer<Int32>? abortSignal}) {
    return _withInput(input, (buffer, captures) {
      final matches = <JsRegExpMatch>[];
      var position = start;
      while (position <= input.length) {
        final match = _exec(input, buffer, position, abortSignal, captures);
        if (match == null) break;
        matches.add(match);
        // 空匹配之后前进一个字符，Unicode 模式下一个代理对算一个字符，和 JS、Java 一致
        position = match.end > match.start ? match.end : _advance(input, match.end);
      }
      return matches;
    });
  }

  void dispose() {
    if (_bytecode == nullptr) return;
    _bindings.qjs_regexp_free(_engine._engine, _bytecode);
    _bytecode = nullptr;
    _engine._regExps.remove(this);
  }

  T _withInput<T>(String input, T Function(Pointer<Uint16> buffer, Pointer<Int32> captures) body) {
    if (_bytecode == nullptr) throw StateError('JsRegExp 已释放');
    _engine._checkAlive();
    // 空串也分配 1 个单元，避免 calloc(0) 返回空指针
    final buffer = malloc<Uint16>(input.isEmpty ? 1 : input.length);
    final captures = malloc<Int32>((groupCount + 1) * 2);
    try {
      buffer.asTypedList(input.length).setAll(0, input.codeUnits);
      return body(buffer, captures);
    } finally {
      malloc.free(buffer);
      malloc.free(captures);
    }
  }

  JsRegExpMatch? _exec(
    String input,
    Pointer<Uint16> buffer,
    int start,
    Pointer<Int32>? abortSignal,
    Pointer<Int32> captures,
  ) {
    RangeError.checkValueInInterval(start, 0, input.length, 'start');
    final rc = _bindings.qjs_regexp_exec(
      _engine._engine,
      _bytecode,
      buffer,
      input.length,
      start,
      abortSignal ?? nullptr,
      captures,
    );
    switch (rc) {
      case 1:
        return JsRegExpMatch._(this, input, Int32List.fromList(captures.asTypedList((groupCount + 1) * 2)));
      case 0:
        return null;
      case -1:
        throw JsException('interrupted');
      default:
        throw JsException('正则执行失败：内存不足');
    }
  }

  int _advance(String input, int index) {
    if (_unicode &&
        index + 1 < input.length &&
        _isHighSurrogate(input.codeUnitAt(index)) &&
        _isLowSurrogate(input.codeUnitAt(index + 1))) {
      return index + 2;
    }
    return index + 1;
  }

  static bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
  static bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

  /// libregexp 在 Unicode 模式下要 UTF-8，在非 Unicode 模式下要 CESU-8（和 QuickJS 的 `JS_ToCStringLen2` 一致）：
  /// BMP 以外的字符拆成两个代理项，各自按 3 字节编码，这样它们在正则里是两个 UTF-16 单元。
  static Pointer<Uint8> _encodePattern(String pattern, {required bool unicode, required Allocator allocator}) {
    final bytes = <int>[];
    void add(int c) {
      if (c < 0x80) {
        bytes.add(c);
      } else if (c < 0x800) {
        bytes.addAll([0xC0 | (c >> 6), 0x80 | (c & 0x3F)]);
      } else if (c < 0x10000) {
        bytes.addAll([0xE0 | (c >> 12), 0x80 | ((c >> 6) & 0x3F), 0x80 | (c & 0x3F)]);
      } else {
        bytes.addAll([0xF0 | (c >> 18), 0x80 | ((c >> 12) & 0x3F), 0x80 | ((c >> 6) & 0x3F), 0x80 | (c & 0x3F)]);
      }
    }

    if (unicode) {
      pattern.runes.forEach(add);
    } else {
      pattern.codeUnits.forEach(add);
    }
    final out = allocator<Uint8>(bytes.length + 1);
    out.asTypedList(bytes.length).setAll(0, bytes);
    out[bytes.length] = 0;
    return out;
  }

  static String? _takeString(Pointer<Char> pointer) {
    if (pointer == nullptr) return null;
    final text = pointer.cast<Utf8>().toDartString();
    _bindings.qjs_free_string(pointer);
    return text;
  }
}

/// [JsRegExp] 的一次匹配。下标都是 UTF-16 单元的下标。
class JsRegExpMatch {
  JsRegExpMatch._(this.regExp, this.input, this._ranges);

  final JsRegExp regExp;
  final String input;

  // 第 i 组的起止位置在 2i、2i+1 处，未参与匹配的组为 -1
  final Int32List _ranges;

  int get start => _ranges[0];
  int get end => _ranges[1];
  int get groupCount => regExp.groupCount;

  /// 第 [index] 组的起点，未参与匹配时为 -1。
  int groupStart(int index) => _ranges[_checkGroup(index) * 2];

  /// 第 [index] 组的终点，未参与匹配时为 -1。
  int groupEnd(int index) => _ranges[_checkGroup(index) * 2 + 1];

  /// 第 [index] 组的文本，未参与匹配时为 null。
  String? group(int index) {
    final from = groupStart(index);
    return from < 0 ? null : input.substring(from, groupEnd(index));
  }

  /// 命名分组的文本。没有这个组名时抛出 [ArgumentError]，未参与匹配时为 null。
  String? namedGroup(String name) {
    final index = regExp.groupIndex(name);
    if (index == null) throw ArgumentError.value(name, 'name', '没有这个命名分组');
    return group(index);
  }

  int _checkGroup(int index) => RangeError.checkValueInInterval(index, 0, groupCount, 'index');
}
