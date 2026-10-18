import 'dart:collection';
import 'dart:typed_data';

import 'package:html/dom.dart';

import '../core/errors.dart';
import '../json/json_text.dart';
import '../rule/content.dart';

/// JS 与规则引擎之间的值：跨边界一律是 JSON，Dart 侧的对象用带标记的 JSON 对象表示（见 `prelude.dart`）。

const String handleTag = '\u0000h';
const String elementsTag = '\u0000e';
const String hostObjectTag = '\u0000o';
const String numberTag = '\u0000n';

/// JSON 对象（MD3 里是 Java Map）在 Java 里的 `toString`：书源常写 `String(result).match(...)`。
const String javaStringTag = '\u0000s';

/// JS 返回的普通对象（MD3 的 NativeObject）。规则引擎把它当作「JS 对象内容」：字段规则只用第一段，
/// 按键取值、JSONPath 或 JS，不和 JSONPath 取到的 JSON 对象混用。转字符串是 `[object Object]`。
final class JsObject extends MapBase<String, Object?> {
  JsObject(this._fields);

  final Map<String, Object?> _fields;

  @override
  Object? operator [](Object? key) => _fields[key];

  @override
  void operator []=(String key, Object? value) => _fields[key] = value;

  @override
  void clear() => _fields.clear();

  @override
  Iterable<String> get keys => _fields.keys;

  @override
  Object? remove(Object? key) => _fields.remove(key);

  @override
  String toString() => '[object Object]';
}

/// JS 返回的数组：可以当列表用，转字符串按 JS 的 `String()`（逗号连接）。
final class JsArray extends ListBase<Object?> {
  JsArray(this._items);

  final List<Object?> _items;

  @override
  int get length => _items.length;

  @override
  set length(int value) => _items.length = value;

  @override
  Object? operator [](int index) => _items[index];

  @override
  void operator []=(int index, Object? value) => _items[index] = value;

  @override
  void add(Object? element) => _items.add(element);

  @override
  String toString() => _items.map((item) => item == null ? '' : jsString(item)).join(',');
}

/// JS 返回的非整数（或超出整数范围的）数字，转字符串按 JS 的数字格式。整数值的数字解码成 [int]。
final class JsNumber {
  const JsNumber(this.value);

  final double value;

  @override
  String toString() => jsNumberString(value);

  @override
  bool operator ==(Object other) => other is JsNumber && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// JS 的 `Number.prototype.toString()`：整数值（绝对值小于 1e21）不带小数点，其余用最短的往返表示。
String jsNumberString(num value) {
  if (value is int) return value.toString();
  final v = value as double;
  if (v.isNaN) return 'NaN';
  if (v.isInfinite) return v > 0 ? 'Infinity' : '-Infinity';
  if (v == 0) return '0';
  if (v == v.truncateToDouble() && v.abs() < 1e21) return v.toStringAsFixed(0);
  // Dart 的 double.toString 与 JS 一致：指数小于 -6 或不小于 21 时用科学计数法，如 1e-7、1e+21
  return v.toString();
}

/// JS 的 `String(x)`（x 不为 null）。元素等 Dart 侧的对象按 MD3 里 Java 对象的 `toString`（[contentToString]）。
String jsString(Object value) => switch (value) {
  String() => value,
  bool() => '$value',
  num() => jsNumberString(value),
  _ => contentToString(value),
};

/// 任务里交给 JS 的 Dart 对象（元素、响应、加密器）：登记后得到编号，JS 侧凭编号调用方法。
///
/// 编号在整个 isolate 里递增，不会重复：任务结束后这张表随任务丢弃，之后再用旧编号（比如 jsLib 状态里留着的）
/// 查不到对象，以「对象已失效」结束，不会误拿到新任务里的对象。
final class HandleTable {
  static int _nextId = 1;

  final Map<int, Object> _objects = {};
  final Map<Object, int> _ids = Map.identity();

  /// 同一个对象只登记一次。
  int add(Object object) => _ids.putIfAbsent(object, () {
    final id = _nextId++;
    _objects[id] = object;
    return id;
  });

  T get<T>(int id) {
    final object = _objects[id];
    if (object is T) return object;
    throw JsEvalException(object == null ? '对象已失效' : '对象类型不对');
  }
}

/// Dart 值转成交给 JS 的 JSON 值。元素、响应、加密器登记到 [handles]。
/// [hostObject] 把 Dart 侧的书籍、章节等转成宿主对象标记，返回 null 时按普通值处理。
Object? toJsValue(Object? value, HandleTable handles, {Object? Function(Object value)? hostObject}) {
  Object? convert(Object? value) {
    if (value == null || value is bool || value is String || value is int) return value;
    if (hostObject != null) {
      final tag = hostObject(value);
      if (tag != null) return tag;
    }
    return switch (value) {
      double() => value.isFinite ? value : {numberTag: jsNumberString(value)},
      JsNumber() => convert(value.value),
      Uint8List() => [for (final byte in value) byte.toSigned(8)],
      RegexMatchGroups() => value.groups,
      ElementList() => {elementsTag: [for (final node in value.elements) handles.add(node)]},
      XPathNodeList() => [for (final item in value.items) convert(item)],
      Node() => {handleTag: handles.add(value), 't': 'el'},
      List() => [for (final item in value) convert(item)],
      // JS 交回的对象原样回去；其余的 Map（JSONPath 取到的对象等）在 MD3 里是 Java Map，带上它的 toString
      JsObject() => {for (final MapEntry(:key, value: v) in value.entries) key: convert(v)},
      Map() => {
        for (final MapEntry(:key, value: v) in value.entries) '$key': convert(v),
        javaStringTag: jaywayString(value),
      },
      JsHandle() => {handleTag: handles.add(value), 't': value.jsType},
      _ => throw ArgumentError('无法交给 JS 的值：${value.runtimeType}'),
    };
  }

  return convert(value);
}

/// 通过句柄交给 JS 的 Dart 对象（响应、加密器）：[jsType] 是预置 JS 里包装类的种类。
abstract interface class JsHandle {
  String get jsType;
}

/// JS 交回的 JSON 值转成 Dart 值：句柄还原成原来的对象，元素列表是 [ElementList]，
/// 普通对象是 [JsObject]，数组是 [JsArray]，非整数的数字是 [JsNumber]。
/// [hostObject] 把宿主对象标记（书籍、章节、书源）还原成 Dart 侧的对象。
Object? fromJsValue(Object? value, HandleTable handles, {Object? Function(String kind)? hostObject}) {
  Object? convert(Object? value) => switch (value) {
    null || bool() || String() || int() => value,
    double() => value == value.truncateToDouble() && value.abs() < 9.2e18 ? value.toInt() : JsNumber(value),
    List() => JsArray([for (final item in value) convert(item)]),
    Map() when value.containsKey(handleTag) => handles.get<Object>(value[handleTag] as int),
    Map() when value.containsKey(elementsTag) => ElementList([
      for (final id in value[elementsTag] as List) handles.get<Node>(id as int),
    ]),
    Map() when value.containsKey(numberTag) => JsNumber(double.parse(value[numberTag] as String)),
    Map() when value.containsKey(hostObjectTag) => hostObject?.call(value[hostObjectTag] as String),
    Map() => JsObject({for (final MapEntry(:key, value: v) in value.entries) '$key': convert(v)}),
    _ => value,
  };

  return convert(value);
}
