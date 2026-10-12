import 'dart:convert';
import 'dart:typed_data';

import 'package:rule_engine/rule_engine.dart';
import 'package:rule_engine/src/request/response_decoder.dart';
import 'package:rule_engine/src/text/gbk.dart';
import 'package:test/test.dart';

// source-request 规格「响应解码」的场景，行为对照 MD3 的 ResponseBody.text()
void main() {
  HttpResult result(List<int> body, [Map<String, String> headers = const {}]) =>
      HttpResult(statusCode: 200, url: 'https://a.com/', headers: headers, body: Uint8List.fromList(body));

  test('去掉 UTF-8 BOM', () {
    expect(decodeResponseBody(result([0xEF, 0xBB, 0xBF, ...utf8.encode('中文')])), '中文');
  });

  test('响应头的 charset 优先', () {
    final body = gbk.encode('<head><meta charset="utf-8"></head>三体');
    expect(decodeResponseBody(result(body, {'content-type': 'text/html; charset="GBK"'})), contains('三体'));
  });

  test('meta 声明 GBK', () {
    final body = gbk.encode('<html><head><meta charset="gbk"><title>三体</title></head></html>');
    expect(decodeResponseBody(result(body, {'content-type': 'text/html'})), contains('<title>三体</title>'));
  });

  test('http-equiv 声明', () {
    final body = gbk.encode('<head><meta http-equiv="Content-Type" content="text/html; charset=gb2312"></head>三体');
    expect(decodeResponseBody(result(body)), endsWith('三体'));
  });

  test('没有任何声明的 GBK 页面', () {
    expect(decodeResponseBody(result(gbk.encode('<p>三体</p>'))), '<p>三体</p>');
  });

  test('没有声明的 UTF-8 页面', () {
    expect(decodeResponseBody(result(utf8.encode('<p>三体</p>'))), '<p>三体</p>');
  });

  test('无法识别的编码名按没有声明处理', () {
    expect(decodeResponseBody(result(gbk.encode('三体'), {'content-type': 'text/html; charset=bogus'})), '三体');
    // http-equiv 的 content 里没有 charset= 时，MD3 把整段当编码名而出错（D12）
    final body = gbk.encode('<head><meta http-equiv="content-type" content="text/html"></head>三体');
    expect(decodeResponseBody(result(body)), endsWith('三体'));
  });

  test('<head> 写成带属性时用正则找 head', () {
    final body = gbk.encode('<html><head lang="zh"><meta charset="gbk"></head>三体</html>');
    // 字面量 <head> 找不到，正则也要求 <head>，所以落到猜测：GBK 字节不是合法 UTF-8
    expect(decodeResponseBody(result(body)), contains('三体'));
  });

  test('XML 响应补上声明', () {
    expect(decodeResponseBody(result(utf8.encode('<a/>'), {'content-type': 'application/xml'})), '<?xml version="1.0"?><a/>');
    expect(decodeResponseBody(result(utf8.encode('<?xml version="1.0"?><a/>'), {'content-type': 'text/xml'})), '<?xml version="1.0"?><a/>');
    expect(decodeResponseBody(result(utf8.encode('<a/>'), {'content-type': 'text/html'})), '<a/>');
  });

  test('type 选项返回小写十六进制', () {
    expect(hexResponseBody(result([0x00, 0xAB, 0x10])), '00ab10');
  });
}
