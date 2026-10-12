/// jsoup `Parser.xmlParser()` 的对应物：把 XML 解析成 `package:html` 的 DOM。
///
/// 和 jsoup 的 XmlTreeBuilder 一样：标签名保留大小写，不做 HTML 的结构修正；结束标签找不到对应的开始标签时忽略；
/// CDATA 按文本处理；`<?xml?>`、`<!DOCTYPE>` 不进入 DOM。实体按 HTML 4 和数字实体解码。
/// 解析出的文档在序列化时按 jsoup 的 XML 输出设置（不缩进、xhtml 转义）处理，见 [isXmlNode]。
library;

import 'package:html/dom.dart';

import '../text/html_unescape.dart';

final Expando<bool> _xmlDocuments = Expando('xml');

/// 用 `<x/>` 写法自闭合的元素，序列化成 `<x />`。
final Expando<bool> _selfClosing = Expando('selfClosing');

/// [parseXml] 创建的元素。jsoup 的 XML 解析器给标签用 XML 命名空间，所以 HTML 标签的块级、空元素等设置都不适用。
final Expando<bool> _xmlElements = Expando('xmlElement');

bool isXmlElement(Element element) => _xmlElements[element] == true;

/// 节点属于 [parseXml] 解析出的文档。
bool isXmlNode(Node node) {
  Node? current = node;
  while (current != null && current is! Document) {
    current = current.parentNode;
  }
  return current != null && _xmlDocuments[current] == true;
}

/// 元素在源码里写成了 `<x/>`。
bool isSelfClosingXmlElement(Element element) => _selfClosing[element] == true;

Document parseXml(String text) {
  final document = Document();
  _xmlDocuments[document] = true;
  final stack = <Node>[document];
  var pos = 0;

  void addText(String raw, {bool decode = true}) {
    if (raw.isEmpty) return;
    stack.last.append(Text(decode ? unescapeHtml4(raw) : raw));
  }

  while (pos < text.length) {
    final lt = text.indexOf('<', pos);
    if (lt < 0) {
      addText(text.substring(pos));
      break;
    }
    addText(text.substring(pos, lt));
    if (text.startsWith('<!--', lt)) {
      final end = text.indexOf('-->', lt + 4);
      final close = end < 0 ? text.length : end;
      stack.last.append(Comment(text.substring(lt + 4, close)));
      pos = end < 0 ? text.length : end + 3;
    } else if (text.startsWith('<![CDATA[', lt)) {
      final end = text.indexOf(']]>', lt + 9);
      addText(text.substring(lt + 9, end < 0 ? text.length : end), decode: false);
      pos = end < 0 ? text.length : end + 3;
    } else if (text.startsWith('<?', lt) || text.startsWith('<!', lt)) {
      final end = text.indexOf('>', lt);
      pos = end < 0 ? text.length : end + 1;
    } else if (text.startsWith('</', lt)) {
      final end = text.indexOf('>', lt);
      final name = text.substring(lt + 2, end < 0 ? text.length : end).trim();
      pos = end < 0 ? text.length : end + 1;
      // 弹出到同名元素；找不到时忽略这个结束标签
      for (var i = stack.length - 1; i > 0; i--) {
        if ((stack[i] as Element).localName == name) {
          stack.removeRange(i, stack.length);
          break;
        }
      }
    } else {
      final tag = _readStartTag(text, lt);
      if (tag == null) {
        // 不是标签：按文本处理这个 <
        addText('<');
        pos = lt + 1;
        continue;
      }
      final element = Element.tag(tag.name);
      _xmlElements[element] = true;
      for (final MapEntry(:key, :value) in tag.attributes.entries) {
        element.attributes[key] = value;
      }
      stack.last.append(element);
      if (tag.selfClosing) {
        _selfClosing[element] = true;
      } else {
        stack.add(element);
      }
      pos = tag.end;
    }
  }
  return document;
}

typedef _StartTag = ({String name, Map<String, String> attributes, bool selfClosing, int end});

final RegExp _name = RegExp(r'[^\s/>=]+');

_StartTag? _readStartTag(String text, int lt) {
  final nameMatch = _name.matchAsPrefix(text, lt + 1);
  if (nameMatch == null) return null;
  final attributes = <String, String>{};
  var pos = nameMatch.end;
  while (pos < text.length) {
    while (pos < text.length && _isSpace(text.codeUnitAt(pos))) {
      pos++;
    }
    if (pos >= text.length) break;
    if (text.startsWith('/>', pos)) {
      return (name: nameMatch.group(0)!, attributes: attributes, selfClosing: true, end: pos + 2);
    }
    if (text[pos] == '>') {
      return (name: nameMatch.group(0)!, attributes: attributes, selfClosing: false, end: pos + 1);
    }
    final attribute = _name.matchAsPrefix(text, pos);
    if (attribute == null) {
      pos++;
      continue;
    }
    pos = attribute.end;
    while (pos < text.length && _isSpace(text.codeUnitAt(pos))) {
      pos++;
    }
    var value = '';
    if (pos < text.length && text[pos] == '=') {
      pos++;
      while (pos < text.length && _isSpace(text.codeUnitAt(pos))) {
        pos++;
      }
      if (pos < text.length && (text[pos] == '"' || text[pos] == "'")) {
        final quote = text[pos];
        final end = text.indexOf(quote, pos + 1);
        value = text.substring(pos + 1, end < 0 ? text.length : end);
        pos = end < 0 ? text.length : end + 1;
      } else {
        final start = pos;
        while (pos < text.length && !_isSpace(text.codeUnitAt(pos)) && text[pos] != '>') {
          pos++;
        }
        value = text.substring(start, pos);
      }
    }
    attributes.putIfAbsent(attribute.group(0)!, () => unescapeHtml4(value));
  }
  return (name: nameMatch.group(0)!, attributes: attributes, selfClosing: false, end: text.length);
}

bool _isSpace(int c) => c == 0x20 || c == 0x9 || c == 0xA || c == 0xD || c == 0xC;
