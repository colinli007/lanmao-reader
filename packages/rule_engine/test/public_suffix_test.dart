import 'package:rule_engine/src/net/public_suffix.dart';
import 'package:test/test.dart';

void main() {
  final list = PublicSuffixList.instance;

  test('普通规则', () {
    expect(list.effectiveTldPlusOne('www.a.com'), 'a.com');
    expect(list.effectiveTldPlusOne('x.com.cn'), 'x.com.cn');
    expect(list.effectiveTldPlusOne('m.x.com.cn'), 'x.com.cn');
    expect(list.effectiveTldPlusOne('a.b.c.example.co.uk'), 'example.co.uk');
  });

  test('主机本身是公共后缀', () {
    expect(list.effectiveTldPlusOne('com.cn'), isNull);
    expect(list.effectiveTldPlusOne('com'), isNull);
  });

  test('通配符和例外规则', () {
    // *.ck 和 !www.ck
    expect(list.effectiveTldPlusOne('a.b.ck'), 'a.b.ck');
    expect(list.effectiveTldPlusOne('b.ck'), isNull);
    expect(list.effectiveTldPlusOne('www.ck'), 'www.ck');
    expect(list.effectiveTldPlusOne('a.www.ck'), 'www.ck');
  });

  test('列表里没有的顶级域按 * 处理', () {
    expect(list.effectiveTldPlusOne('a.b.unknowntld'), 'b.unknowntld');
  });

  test('私有部分和 OkHttp 一样生效', () {
    expect(list.effectiveTldPlusOne('foo.github.io'), 'foo.github.io');
  });

  test('Cookie 分组域名', () {
    expect(cookieDomain('https://www.a.com/book/1'), 'a.com');
    expect(cookieDomain('http://m.a.com:8080'), 'a.com');
    expect(cookieDomain('http://www.biquge.com.cn/x'), 'biquge.com.cn');
    expect(cookieDomain('http://1.2.3.4:8080/x'), '1.2.3.4');
    expect(cookieDomain('http://[::1]/x'), '::1');
    expect(cookieDomain('https://com.cn/'), 'com.cn');
    expect(cookieDomain('a.com/x'), 'a.com/x');
  });
}
