import 'package:html/dom.dart';

import '../html/jsoup_text.dart';
import '../html/xpath.dart';
import '../json/json_text.dart';

/// AllInOne 正则列表的一项：一个匹配的全部分组，未参与匹配的组为空串。
///
/// 和 JSON 数组区分开：两者在 MD3 里都是 `List`，但来源和用途不同。
final class RegexMatchGroups {
  const RegexMatchGroups(this.groups);

  final List<String> groups;

  /// Kotlin `List.toString()`。
  @override
  String toString() => '[${groups.join(', ')}]';
}

/// 详情 `init` 用 JSoup 规则取到的元素列表（jsoup 的 `Elements`）：转字符串是各元素的 outerHtml 用换行连接，
/// 之后的字段规则在重新解析的这段 HTML 上取值，和 MD3 一致。
final class ElementList {
  const ElementList(this.elements);

  final List<Node> elements;

  @override
  String toString() => jsoupOuterHtmlAll(elements);
}

/// 详情 `init` 用 XPath 取到的结果列表（Java 的 `ArrayList<JXNode>`）：转字符串是 `[a, b]`。
final class XPathNodeList {
  const XPathNodeList(this.items);

  final List<Object> items;

  @override
  String toString() => '[${items.map(xpathNodeString).join(', ')}]';
}

/// MD3 里 `content.toString()` 的结果：元素是 jsoup 的 `outerHtml`（XPath 取到的文本伪元素取文本），
/// JSON 值照 json-path 的输出，正则项是 Kotlin 列表的格式。
String contentToString(Object? content) => switch (content) {
  String() => content,
  Node() => xpathNodeString(content),
  RegexMatchGroups() || ElementList() || XPathNodeList() => content.toString(),
  _ => jaywayString(content),
};

/// MD3 的 `isJSON`：元素不算；其余内容转成字符串后，去掉首尾空白以 `{}` 或 `[]` 包裹。
bool isJsonContent(Object? content) => content is! Node && isJsonText(contentToString(content));

/// MD3 的 `String.isJson()`。
bool isJsonText(String text) {
  final trimmed = text.trim();
  return (trimmed.startsWith('{') && trimmed.endsWith('}')) || (trimmed.startsWith('[') && trimmed.endsWith(']'));
}
