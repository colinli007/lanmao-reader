import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../core/environment.dart';
import '../core/errors.dart';
import '../html/xml_parser.dart';
import '../html/xpath.dart';
import 'content.dart';
import 'rule_splitter.dart';

/// MD3 的 `AnalyzeByXPath`：用 JsoupXpath 的语义取值。
///
/// 结果项是元素（[Element]）或字符串等值；转成字符串时文本伪元素取文本，其它元素取 outerHtml。
final class AnalyzeByXPath {
  AnalyzeByXPath(this._env, Object? content) : _context = _parse(content);

  final RuleEnvironment _env;
  final List<Element> _context;

  /// 元素直接作为上下文；文档取它的子元素；其余内容转成字符串后解析：以 `</td>` 结尾时外面补 `<tr>`，
  /// 以 `</tr>`、`</tbody>` 结尾时补 `<table>`，去掉首尾空白后以 `<?xml` 开头时按 XML 解析。
  static List<Element> _parse(Object? content) {
    if (content is Element) return [content];
    if (content is Document) return content.children;
    var html = contentToString(content);
    if (html.endsWith('</td>')) html = '<tr>$html</tr>';
    if (html.endsWith('</tr>') || html.endsWith('</tbody>')) html = '<table>$html</table>';
    final document = html.trim().toLowerCase().startsWith('<?xml') ? parseXml(html) : html_parser.parse(html);
    return document.children;
  }

  List<Object> _result(String xPath) {
    try {
      return XPath.parse(xPath).select(_env, _context);
    } on FormatException catch (e) {
      throw RuleException('不支持的 XPath：$xPath（${e.message}）');
    }
  }

  List<Object> getElements(String xPath) {
    if (xPath.isEmpty) return [];
    final splitter = RuleSplitter(xPath);
    final rules = splitter.splitRule(const ['&&', '||', '%%']);
    if (rules.length == 1) return _result(rules.single);
    final results = <List<Object>>[];
    for (final rl in rules) {
      final temp = getElements(rl);
      if (temp.isNotEmpty) {
        results.add(temp);
        if (splitter.elementsType == '||') break;
      }
    }
    return _merge(results, splitter.elementsType);
  }

  List<String> getStringList(String xPath) {
    final splitter = RuleSplitter(xPath);
    final rules = splitter.splitRule(const ['&&', '||', '%%']);
    if (rules.length == 1) return _result(xPath).map(xpathNodeString).toList();
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

  /// 取字符串：各项用换行连接。按 `&&`、`||` 切分（不认 `%%`）。
  String? getString(String rule) {
    final splitter = RuleSplitter(rule);
    final rules = splitter.splitRule(const ['&&', '||']);
    if (rules.length == 1) return _result(rule).map(xpathNodeString).join('\n');
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

  static List<T> _merge<T>(List<List<T>> results, String type) {
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
