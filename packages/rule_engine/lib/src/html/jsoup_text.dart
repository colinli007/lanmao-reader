/// jsoup 1.16.2 的文本取值和 HTML 序列化，作用在 `package:html` 的 DOM 上。
///
/// 照 jsoup 源码移植：`Element.text()`、`ownText()`、`TextNode.text()`、`data()`，以及默认输出设置
/// （prettyPrint、缩进 1 格、最大缩进 30、base 转义模式、UTF-8）下的 `outerHtml()`。
/// 和 jsoup 的对应关系：`Document` 相当于 jsoup 的根元素 `#root`；HTML 文档里 `script`、`style` 的文本相当于 jsoup 的 DataNode。
/// [parseXml] 解析出的文档按 jsoup 的 XML 输出设置序列化：不缩进、xhtml 转义、不合并布尔属性。
library;

import 'package:html/dom.dart';

import 'xml_parser.dart';

/// `Element.text()`：合并空白，块级元素之间补空格，去掉首尾空白。
String jsoupText(Node root) {
  final out = _TextBuffer();
  _accumulateText(root, out, siblings: null, index: -1, xml: isXmlNode(root));
  return _trimJava(out.toString());
}

void _accumulateText(
  Node node,
  _TextBuffer out, {
  required List<Node>? siblings,
  required int index,
  required bool xml,
}) {
  if (node is Text) {
    if (!_isDataNode(node, xml)) _appendNormalisedText(out, node);
    return;
  }
  if (node is Element && out.isNotEmpty && (_isBlock(node) || node.localName == 'br') && !_endsWithSpace(out)) {
    out.write(' ');
  }
  final children = node.nodes;
  for (var i = 0; i < children.length; i++) {
    _accumulateText(children[i], out, siblings: children, index: i, xml: xml);
  }
  // 块级元素和紧跟其后的文本或行内元素之间补空格：<div>One</div>Two 得到 "One Two"
  if (node is Element && _isBlock(node) && siblings != null && index + 1 < siblings.length) {
    final next = siblings[index + 1];
    if ((next is Text || next is Element && !_formatAsBlock(next)) && !_endsWithSpace(out)) out.write(' ');
  }
}

/// `Element.ownText()`：只取直接子文本，`br` 算一个空格。
String jsoupOwnText(Node element) {
  final out = _TextBuffer();
  final xml = isXmlNode(element);
  for (final child in element.nodes) {
    if (child is Text) {
      if (!_isDataNode(child, xml)) _appendNormalisedText(out, child);
    } else if (child is Element && child.localName == 'br' && !_endsWithSpace(out)) {
      out.write(' ');
    }
  }
  return _trimJava(out.toString());
}

/// `Element.textNodes()` 里每个文本节点的 `text()`（合并空白，不去首尾空白）。
List<String> jsoupTextNodes(Node element) {
  final xml = isXmlNode(element);
  return [
    for (final child in element.nodes)
      if (child is Text && !_isDataNode(child, xml)) _normaliseWhitespace(child.data),
  ];
}

/// `Element.data()`：脚本、样式的内容和注释。
String jsoupData(Node root) {
  final out = StringBuffer();
  final xml = isXmlNode(root);
  void visit(Node node) {
    if (node is Text && _isDataNode(node, xml)) out.write(node.data);
    if (node is Comment) out.write(node.data ?? '');
    node.nodes.forEach(visit);
  }

  root.nodes.forEach(visit);
  if (root is Comment) out.write(root.data ?? '');
  return out.toString();
}

/// `Element.outerHtml()`，按 jsoup 的默认输出设置格式化。`Document` 输出它的全部子节点（jsoup 的 `Document.outerHtml()`）。
String jsoupOuterHtml(Node node) {
  final out = StringBuffer();
  final writer = _HtmlWriter(out, xml: isXmlNode(node));
  if (node is Document) {
    final children = node.nodes;
    for (var i = 0; i < children.length; i++) {
      writer.write(children[i], 0, children, i);
    }
    return writer.xml ? out.toString() : _trimJava(out.toString());
  }
  final siblings = node.parentNode?.nodes;
  writer.write(node, 0, siblings ?? [node], siblings?.indexOf(node) ?? 0);
  return out.toString();
}

/// `Elements.outerHtml()`：各元素的 outerHtml 用换行连接。
String jsoupOuterHtmlAll(Iterable<Node> nodes) => nodes.map(jsoupOuterHtml).join('\n');

/// jsoup 的元素名：`Document` 是 `#root`。
String jsoupTagName(Node node) => node is Element ? node.localName ?? '' : '#root';

/// jsoup 的 `Tag.isBlock()`：已知块级标签为真，行内标签和未知标签为假。
bool jsoupIsBlock(Node node) => _isBlock(node);

// ---------------------------------------------------------------- 序列化

final class _HtmlWriter {
  _HtmlWriter(this.out, {required this.xml});

  final StringBuffer out;

  /// XML 文档：不缩进，xhtml 转义，不合并布尔属性，`<x/>` 输出成 `<x />`。
  final bool xml;

  void write(Node node, int depth, List<Node> siblings, int index) {
    switch (node) {
      case Element():
        _elementHead(node, depth, siblings, index);
        final children = node.nodes;
        for (var i = 0; i < children.length; i++) {
          write(children[i], depth + 1, children, i);
        }
        _elementTail(node, depth);
      case Text() when _isDataNode(node, xml):
        out.write(node.data);
      case Text() when xml:
        _escape(node.data, inAttribute: false);
      case Text():
        _textHead(node, depth, siblings, index);
      case Comment():
        final parent = node.parentNode;
        if (!xml && _isEffectivelyFirst(siblings, index) && parent is Element && _formatAsBlock(parent)) {
          _indent(depth);
        }
        out.write('<!--${node.data ?? ''}-->');
      case DocumentType():
        if (index > 0) out.write('\n');
        out.write('<!doctype ${node.name ?? ''}>');
      default:
        for (final child in node.nodes) {
          write(child, depth + 1, node.nodes, node.nodes.indexOf(child));
        }
    }
  }

  void _elementHead(Element element, int depth, List<Node> siblings, int index) {
    if (!xml && _shouldIndent(element, siblings, index) && out.isNotEmpty) _indent(depth);
    final name = element.localName;
    out.write('<$name');
    for (final MapEntry(:key, :value) in element.attributes.entries) {
      final attribute = '$key';
      out.write(' $attribute');
      final collapse =
          !xml &&
          (value.isEmpty || value.toLowerCase() == attribute.toLowerCase()) &&
          _booleanAttributes.contains(attribute.toLowerCase());
      if (!collapse) {
        out.write('="');
        _escape(value, inAttribute: true);
        out.write('"');
      }
    }
    out.write(element.nodes.isEmpty && _isSelfClosing(element) && xml ? ' />' : '>');
  }

  bool _isSelfClosing(Element element) => _isEmptyTag(element) || (xml && isSelfClosingXmlElement(element));

  void _elementTail(Element element, int depth) {
    if (element.nodes.isEmpty && _isSelfClosing(element)) return;
    if (xml) {
      out.write('</${element.localName}>');
      return;
    }
    if (element.nodes.isNotEmpty && _formatAsBlock(element) && !_preserveWhitespace(element.parentNode)) {
      _indent(depth);
    }
    out.write('</${element.localName}>');
  }

  void _textHead(Text text, int depth, List<Node> siblings, int index) {
    final parentNode = text.parentNode;
    final parent = parentNode is Element ? parentNode : null;
    final normaliseWhite = !_preserveWhitespace(parentNode);
    final trimLikeBlock = parent != null && (_isBlock(parent) || _formatAsBlock(parent));
    var trimLeading = false;
    var trimTrailing = false;
    final prev = index > 0 ? siblings[index - 1] : null;
    final next = index + 1 < siblings.length ? siblings[index + 1] : null;

    if (normaliseWhite) {
      trimLeading = (trimLikeBlock && index == 0) || parentNode is Document;
      trimTrailing = trimLikeBlock && next == null;

      // 空白文本后面紧跟会换行的节点时，跳过这段空白
      final isBlank = _isBlank(text.data);
      final couldSkip =
          (next is Element && _shouldIndent(next, siblings, index + 1)) ||
          (next is Text && _isBlank(next.data)) ||
          (prev is Element && (_isBlock(prev) || prev.localName == 'br'));
      if (couldSkip && isBlank) return;

      if ((index == 0 && parent != null && _formatAsBlock(parent) && !isBlank) ||
          (index > 0 && prev is Element && prev.localName == 'br')) {
        _indent(depth);
      }
    }
    _escape(
      text.data,
      inAttribute: false,
      normaliseWhite: normaliseWhite,
      stripLeadingWhite: trimLeading,
      trimTrailing: trimTrailing,
    );
  }

  void _indent(int depth) {
    out.write('\n');
    out.write(' ' * (depth < 30 ? depth : 30));
  }

  /// `Entities.escape`，base 转义模式、UTF-8 输出。
  void _escape(
    String text, {
    required bool inAttribute,
    bool normaliseWhite = false,
    bool stripLeadingWhite = false,
    bool trimTrailing = false,
  }) {
    var lastWasWhite = false;
    var reachedNonWhite = false;
    var skipped = false;
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      if (normaliseWhite) {
        if (_isWhitespace(c)) {
          if ((stripLeadingWhite && !reachedNonWhite) || lastWasWhite) continue;
          if (trimTrailing) {
            skipped = true;
            continue;
          }
          out.write(' ');
          lastWasWhite = true;
          continue;
        }
        lastWasWhite = false;
        reachedNonWhite = true;
        if (skipped) {
          out.write(' ');
          skipped = false;
        }
      }
      switch (c) {
        case 0x26:
          out.write('&amp;');
        case 0xA0:
          out.write(xml ? '&#xa0;' : '&nbsp;');
        case 0x3C:
          out.write(inAttribute && !xml ? '<' : '&lt;');
        case 0x3E:
          out.write(inAttribute ? '>' : '&gt;');
        case 0x22:
          out.write(inAttribute ? '&quot;' : '"');
        case 0x9 || 0xA || 0xD:
          out.writeCharCode(c);
        default:
          final isHigh = c >= 0xD800 && c <= 0xDBFF;
          final isLow = c >= 0xDC00 && c <= 0xDFFF;
          if (isHigh && i + 1 < text.length && _isLowSurrogate(text.codeUnitAt(i + 1))) {
            out
              ..writeCharCode(c)
              ..writeCharCode(text.codeUnitAt(++i));
          } else if (c < 0x20 || isHigh || isLow) {
            // 控制字符和落单的代理项 UTF-8 编不了，输出成数字实体
            out.write('&#x${c.toRadixString(16)};');
          } else {
            out.writeCharCode(c);
          }
      }
    }
  }
}

bool _shouldIndent(Element element, List<Node> siblings, int index) =>
    _isFormatAsBlock(element) && !_isInlineable(element, siblings, index) && !_preserveWhitespace(element.parentNode);

bool _isFormatAsBlock(Element element) {
  final parent = element.parentNode;
  return _isBlock(element) || (parent != null && (parent is Element || parent is Document) && _formatAsBlock(parent));
}

bool _isInlineable(Element element, List<Node> siblings, int index) {
  if (_isBlock(element)) return false;
  final parent = element.parentNode;
  return (parent == null || _isBlock(parent)) && !_isEffectivelyFirst(siblings, index) && element.localName != 'br';
}

bool _isEffectivelyFirst(List<Node> siblings, int index) {
  if (index == 0) return true;
  if (index == 1) {
    final prev = siblings[0];
    return prev is Text && !_isDataNode(prev, false) && _isBlank(prev.data);
  }
  return false;
}

// ---------------------------------------------------------------- 标签属性

/// jsoup 只在标签的命名空间和注册时一致时才用已知标签的设置，否则按未知标签处理
/// （HTML 正文里的 `text`、`mi` 等，以及 XML 文档里的全部标签）。
String? _knownTag(Element element) {
  if (isXmlElement(element)) return null;
  final name = element.localName;
  final namespace = switch (name) {
    'svg' || 'text' => _svgNamespace,
    'math' || 'mi' || 'mo' || 'msup' || 'mn' || 'mtext' => _mathNamespace,
    _ => _htmlNamespace,
  };
  return (element.namespaceUri ?? _htmlNamespace) == namespace ? name : null;
}

const String _htmlNamespace = 'http://www.w3.org/1999/xhtml';
const String _svgNamespace = 'http://www.w3.org/2000/svg';
const String _mathNamespace = 'http://www.w3.org/1998/Math/MathML';

bool _isBlock(Node node) => node is Element && _blockTags.contains(_knownTag(node));

/// 未知标签和 `#root` 按块格式化，行内标签和 [_formatAsInlineTags] 按行内格式化。
bool _formatAsBlock(Node node) {
  if (node is! Element) return true;
  final name = _knownTag(node);
  return !_inlineTags.contains(name) && !_formatAsInlineTags.contains(name);
}

bool _isEmptyTag(Element element) => _emptyTags.contains(_knownTag(element));

/// 自己或往上 5 层祖先是 pre、plaintext、title、textarea 时保留空白。
bool _preserveWhitespace(Node? node) {
  var current = node is Element ? node : null;
  for (var i = 0; i < 6 && current != null; i++) {
    if (_preserveWhitespaceTags.contains(_knownTag(current))) return true;
    current = current.parent;
  }
  return false;
}

/// jsoup 的 HTML 解析器把 script、style 的内容解析成 DataNode，不算文本；XML 解析器不区分。
bool _isDataNode(Text text, bool xml) {
  if (xml) return false;
  final parent = text.parentNode;
  return parent is Element && (parent.localName == 'script' || parent.localName == 'style');
}

const Set<String> _blockTags = {
  'html', 'head', 'body', 'frameset', 'script', 'noscript', 'style', 'meta', 'link', 'title', 'frame', //
  'noframes', 'section', 'nav', 'aside', 'hgroup', 'header', 'footer', 'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
  'ul', 'ol', 'pre', 'div', 'blockquote', 'hr', 'address', 'figure', 'figcaption', 'form', 'fieldset', 'ins',
  'del', 'dl', 'dt', 'dd', 'li', 'table', 'caption', 'thead', 'tfoot', 'tbody', 'colgroup', 'col', 'tr', 'th',
  'td', 'video', 'audio', 'canvas', 'details', 'menu', 'plaintext', 'template', 'article', 'main', 'svg', 'math',
  'center', 'dir', 'applet', 'marquee', 'listing',
};

const Set<String> _inlineTags = {
  'object', 'base', 'font', 'tt', 'i', 'b', 'u', 'big', 'small', 'em', 'strong', 'dfn', 'code', 'samp', 'kbd', //
  'var', 'cite', 'abbr', 'time', 'acronym', 'mark', 'ruby', 'rt', 'rp', 'rtc', 'a', 'img', 'br', 'wbr', 'map', 'q',
  'sub', 'sup', 'bdo', 'iframe', 'embed', 'span', 'input', 'select', 'textarea', 'label', 'button', 'optgroup',
  'option', 'legend', 'datalist', 'keygen', 'output', 'progress', 'meter', 'area', 'param', 'source', 'track',
  'summary', 'command', 'device', 'basefont', 'bgsound', 'menuitem', 'data', 'bdi', 's', 'strike', 'nobr', 'rb',
  'text', 'mi', 'mo', 'msup', 'mn', 'mtext',
};

const Set<String> _emptyTags = {
  'meta', 'link', 'base', 'frame', 'img', 'br', 'wbr', 'embed', 'hr', 'input', 'keygen', 'col', 'command', //
  'device', 'area', 'basefont', 'bgsound', 'menuitem', 'param', 'source', 'track',
};

const Set<String> _formatAsInlineTags = {
  'title', 'a', 'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'pre', 'address', 'li', 'th', 'td', 'script', 'style', //
  'ins', 'del', 's',
};

const Set<String> _preserveWhitespaceTags = {'pre', 'plaintext', 'title', 'textarea'};

const Set<String> _booleanAttributes = {
  'allowfullscreen', 'async', 'autofocus', 'checked', 'compact', 'declare', 'default', 'defer', 'disabled', //
  'formnovalidate', 'hidden', 'inert', 'ismap', 'itemscope', 'multiple', 'muted', 'nohref', 'noresize',
  'noshade', 'novalidate', 'nowrap', 'open', 'readonly', 'required', 'reversed', 'seamless', 'selected',
  'sortable', 'truespeed', 'typemustmatch',
};

// ---------------------------------------------------------------- 空白

void _appendNormalisedText(_TextBuffer out, Text text) {
  if (_preserveWhitespace(text.parentNode)) {
    out.write(text.data);
  } else {
    _appendNormalisedWhitespace(out, text.data, stripLeading: _endsWithSpace(out));
  }
}

/// `StringUtil.normaliseWhitespace`（jsoup 的 `TextNode.text()`）：合并空白，不去首尾空白。
String jsoupNormaliseWhitespace(String text) => _normaliseWhitespace(text);

String _normaliseWhitespace(String text) {
  final out = _TextBuffer();
  _appendNormalisedWhitespace(out, text, stripLeading: false);
  return out.toString();
}

/// `StringUtil.appendNormalisedWhitespace`：空白（含 nbsp）合并为一个空格，去掉零宽空格和软连字符。
void _appendNormalisedWhitespace(_TextBuffer out, String text, {required bool stripLeading}) {
  var lastWasWhite = false;
  var reachedNonWhite = false;
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (_isActuallyWhitespace(c)) {
      if ((stripLeading && !reachedNonWhite) || lastWasWhite) continue;
      out.write(' ');
      lastWasWhite = true;
    } else if (c != 0x200B && c != 0xAD) {
      out.writeCharCode(c);
      lastWasWhite = false;
      reachedNonWhite = true;
    }
  }
}

bool _endsWithSpace(_TextBuffer out) => out.last == 0x20;

/// 记住最后一个字符的 [StringBuffer]：jsoup 频繁检查「末尾是不是空格」。
final class _TextBuffer {
  final StringBuffer _buffer = StringBuffer();
  int last = -1;

  bool get isNotEmpty => _buffer.isNotEmpty;

  void write(String text) {
    if (text.isEmpty) return;
    _buffer.write(text);
    last = text.codeUnitAt(text.length - 1);
  }

  void writeCharCode(int c) {
    _buffer.writeCharCode(c);
    last = c;
  }

  @override
  String toString() => _buffer.toString();
}

bool _isWhitespace(int c) => c == 0x20 || c == 0x9 || c == 0xA || c == 0xC || c == 0xD;

bool _isActuallyWhitespace(int c) => _isWhitespace(c) || c == 0xA0;

bool _isLowSurrogate(int c) => c >= 0xDC00 && c <= 0xDFFF;

bool _isBlank(String text) => text.codeUnits.every(_isWhitespace);

/// Java 的 `String.trim()`：去掉首尾不大于空格的字符。
String _trimJava(String text) {
  var start = 0;
  var end = text.length;
  while (start < end && text.codeUnitAt(start) <= 0x20) {
    start++;
  }
  while (end > start && text.codeUnitAt(end - 1) <= 0x20) {
    end--;
  }
  return text.substring(start, end);
}
