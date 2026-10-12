import 'package:rule_engine/src/text/html_unescape.dart';
import 'package:test/test.dart';

void main() {
  test('HTML 4 命名实体', () {
    expect(unescapeHtml4('a &amp; b &lt;c&gt; &quot;d&quot; &nbsp;&copy;&hellip;&euro;'), 'a & b <c> "d"  ©…€');
  });

  test('数字实体必须带分号', () {
    expect(unescapeHtml4('&#20013;&#x6587;&#X41;'), '中文A');
    expect(unescapeHtml4('&#20013 &#x;'), '&#20013 &#x;');
    expect(unescapeHtml4('&#128512;'), '😀');
  });

  test('不认识的实体原样保留', () {
    expect(unescapeHtml4('&apos; &nbsp &NBSP; &bogus; & x'), '&apos; &nbsp &NBSP; &bogus; & x');
  });

  test('lang 和 rang 按 HTML 4 取值', () {
    expect(unescapeHtml4('&lang;&rang;'), '〈〉');
  });

  test('转义后的 & 不再展开', () {
    expect(unescapeHtml4('&amp;lt;'), '&lt;');
  });
}
