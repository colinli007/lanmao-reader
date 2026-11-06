import 'dart:convert';
import 'dart:io';

import 'package:rule_engine/rule_engine.dart';
import 'package:rule_engine/src/core/source_task.dart';
import 'package:rule_engine/src/rule/analyze_rule.dart';
import 'package:test/test.dart';

import 'support/fake_environment.dart';

// 合集 1329 星空小说的原始 ruleContent；省略无关的搜索、请求签名规则。
// 向量由 JDK Cipher AES/CBC/PKCS5Padding 独立生成，key 为原规则中的
// UTF-8 "242ccb8230d709e1"，IV 分别为 0x80..0x8f、0x97..0xa6、0xae..0xbd。
// 响应格式为 Base64(IV + ciphertext)，测试不调用被测引擎生成密文。
const _first =
    'gIGCg4SFhoeIiYqLjI2Oj1pjq8+rsxrfRHGX/OyICn35v0rS/TvRd4RbXOa3BIZr'
    'SRjDszlhZWRmTbIfKwA/pw==';
const _second =
    'l5iZmpucnZ6foKGio6SlpgknOFi8Fi20Y5LTeMGFVaIjMb1QnpOzMJh/2bkZPrhz';
const _empty = 'rq+wsbKztLW2t7i5uru8vXdqVJ5WMlc+/zkloahEVoI=';

void main() {
  late FakeEnvironment env;
  late BookSource source;
  setUp(() {
    env = FakeEnvironment();
    source = loadBookSources(
      File('test/fixtures/xingkong_java_source.json').readAsStringSync(),
    ).sources.single;
  });
  tearDown(() => env.dispose());

  String decode(String encrypted) {
    final rule = AnalyzeRule(SourceTask(env, source))
      ..setContent(_body(encrypted));
    return rule.getString(source.ruleContent['content']);
  }

  test('星空原始 JavaImporter 规则解密 IV 前缀、中文和补充平面字符', () {
    // with 内 String 必须解析为导入的 java.lang.String，支持字符串 getBytes
    // 和 byte[] 构造；不能为测试改写成 java.lang.String 或移出 with。
    expect(decode(_first), '星空正文🚀。\n第二段中文。');
    expect(decode(_second), '另一章：𠮷与é');
    expect(decode(_empty), '');
  });

  test('星空原始规则在不同 SourceTask 之间重复执行不残留 IV 或密文', () {
    expect(decode(_first), '星空正文🚀。\n第二段中文。');
    expect(decode(_second), '另一章：𠮷与é');
    expect(decode(_first), '星空正文🚀。\n第二段中文。');
  });

  test('星空原始规则拒绝非法 Base64、缺失 IV、非整块密文和错误填充', () {
    final badPadding = base64Decode(_empty);
    // 空明文的 CBC 唯一块全为 0x10 填充，翻转 IV 首位保证填充非法。
    badPadding[0] ^= 1;
    final malformed = {
      '非法 Base64': '%%%%',
      '不足 16 字节 IV': base64Encode(List.filled(15, 0)),
      '密文不是 AES 整块': base64Encode(List.filled(17, 0)),
      '错误 PKCS5 填充': base64Encode(badPadding),
    };
    for (final entry in malformed.entries) {
      expect(
        () => decode(entry.value),
        throwsA(isA<JsEvalException>()),
        reason: entry.key,
      );
    }
    // 失败也不能污染接下来的任务。
    expect(decode(_second), '另一章：𠮷与é');
  });

  test('星空合成正文响应经原始规则解密后正常排版', () {
    const bookUrl = 'https://xingkong.test/book/1';
    const chapterUrl = 'https://xingkong.test/chapter/1';
    env.respond(chapterUrl, _body(_first));
    final book = Book.of(source, bookUrl)..tocUrl = '$bookUrl/toc';
    final chapter = BookChapter(bookUrl: bookUrl, baseUrl: book.tocUrl)
      ..url = chapterUrl
      ..title = '第一章 星空';

    final result = getContent(env, source, book, chapter);
    expect(result.title, '第一章 星空');
    expect(result.content, '星空正文🚀。\n　　第二段中文。');
    expect(env.requests.map((request) => request.url), [chapterUrl]);
  });
}

String _body(String encrypted) => jsonEncode({
  'data': {'content': encrypted},
});
