import 'dart:convert';
import 'dart:typed_data';

import 'environment.dart';

/// 主 isolate 回复给 worker 的响应帧：`[4 字节元数据长度][元数据 JSON][响应体]`，批量时多帧依次拼接。
/// 响应体是原始字节，不经过 JSON，解码在 worker 里完成。
Uint8List encodeHttpResults(List<HttpResult> results) {
  final out = BytesBuilder(copy: false);
  for (final result in results) {
    final meta = utf8.encode(
      jsonEncode({
        'status': result.statusCode,
        'url': result.url,
        'headers': result.headers,
        'length': result.body.length,
        'redirected': result.redirected,
      }),
    );
    out
      ..add((ByteData(4)..setUint32(0, meta.length)).buffer.asUint8List())
      ..add(meta)
      ..add(result.body);
  }
  return out.takeBytes();
}

List<HttpResult> decodeHttpResults(Uint8List frame) {
  final results = <HttpResult>[];
  final data = ByteData.sublistView(frame);
  var pos = 0;
  while (pos < frame.length) {
    final metaLength = data.getUint32(pos);
    pos += 4;
    final meta = jsonDecode(utf8.decode(Uint8List.sublistView(frame, pos, pos + metaLength))) as Map<String, Object?>;
    pos += metaLength;
    final length = meta['length'] as int;
    results.add(
      HttpResult(
        statusCode: meta['status'] as int,
        url: meta['url'] as String,
        headers: (meta['headers'] as Map).cast<String, String>(),
        body: Uint8List.sublistView(frame, pos, pos + length),
        redirected: meta['redirected'] as bool,
      ),
    );
    pos += length;
  }
  return results;
}
