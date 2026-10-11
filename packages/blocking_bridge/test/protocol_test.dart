import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:blocking_bridge/src/protocol.dart';
import 'package:test/test.dart';

void main() {
  test('JSON 值往返', () {
    final reply = Reply.decode(encodeValue(7, {'a': [1, '中文', null]}));
    expect(reply.kind, ReplyKind.json);
    expect(reply.requestId, 7);
    expect(reply.value, {'a': [1, '中文', null]});
  });

  test('1MB 原始字节原样往返', () {
    final random = Random(1);
    final bytes = Uint8List.fromList(List.generate(1 << 20, (_) => random.nextInt(256)));
    final reply = Reply.decode(encodeValue(0xffffffff, bytes));
    expect(reply.kind, ReplyKind.bytes);
    expect(reply.requestId, 0xffffffff);
    expect(reply.value, bytes);
  });

  test('错误和已取消', () {
    final error = Reply.decode(encodeError(1, '网络不可用'));
    expect(error.kind, ReplyKind.error);
    expect(error.errorMessage, '网络不可用');

    final cancelled = Reply.decode(encodeCancelled(2));
    expect(cancelled.kind, ReplyKind.cancelled);
    expect(cancelled.requestId, 2);
  });

  test('不能编码成 JSON 的值抛出', () {
    expect(() => encodeValue(1, Object()), throwsA(isA<JsonUnsupportedObjectError>()));
  });
}
