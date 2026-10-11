/// 主 isolate 与 worker 之间的消息。
///
/// 主 → worker 走 SendPort（[TaskMessage]）；worker → 主走 SendPort（[WorkerReady]、[HostRequest]、[TaskDone]）；
/// 宿主请求的回复走 Mailbox，因为那时 worker 正阻塞着，收不了 SendPort 消息，回复编码成二进制帧（[encodeReply]）。
library;

import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:native_synchronization/mailbox.dart';
import 'package:native_synchronization/sendable.dart';

final class WorkerReady {
  const WorkerReady(this.commands, this.mailbox);

  final SendPort commands;
  final Sendable<Mailbox> mailbox;
}

final class TaskMessage {
  const TaskMessage(this.taskId, this.body, this.abortAddress);

  final int taskId;
  final Object? Function() body;

  /// 本任务中止标志（`Int32`）的地址，主侧分配和释放。
  final int abortAddress;
}

final class HostRequest {
  const HostRequest(this.taskId, this.requestId, this.op, this.payload);

  final int taskId;
  final int requestId;
  final String op;
  final Object? payload;
}

final class TaskDone {
  const TaskDone.value(this.taskId, this.value) : error = null, stack = null;

  const TaskDone.error(this.taskId, Object this.error, this.stack) : value = null;

  final int taskId;
  final Object? value;
  final Object? error;
  final String? stack;

  bool get failed => error != null;
}

// ---------------------------------------------------------------- 回复帧

/// 回复帧：`[类型 1 字节][requestId 4 字节][内容]`。
enum ReplyKind {
  /// 内容是 UTF-8 JSON。
  json,

  /// 内容是原始字节，原样交给任务。
  bytes,

  /// 内容是 UTF-8 错误消息。
  error,

  /// 无内容：所属任务已结束。
  cancelled,
}

const int _headerLength = 5;

/// 宿主返回 [Uint8List] 时按原始字节传递，其它值按 JSON 编码（编码失败会抛出）。
Uint8List encodeValue(int requestId, Object? value) => value is Uint8List
    ? encodeReply(requestId, ReplyKind.bytes, value)
    : encodeReply(requestId, ReplyKind.json, utf8.encode(jsonEncode(value)));

Uint8List encodeError(int requestId, String message) =>
    encodeReply(requestId, ReplyKind.error, utf8.encode(message));

Uint8List encodeCancelled(int requestId) => encodeReply(requestId, ReplyKind.cancelled, Uint8List(0));

Uint8List encodeReply(int requestId, ReplyKind kind, Uint8List body) {
  final frame = Uint8List(_headerLength + body.length);
  ByteData.sublistView(frame)
    ..setUint8(0, kind.index)
    ..setUint32(1, requestId);
  frame.setRange(_headerLength, frame.length, body);
  return frame;
}

final class Reply {
  Reply.decode(Uint8List frame)
      : kind = ReplyKind.values[frame[0]],
        requestId = ByteData.sublistView(frame).getUint32(1),
        body = Uint8List.sublistView(frame, _headerLength);

  final ReplyKind kind;
  final int requestId;
  final Uint8List body;

  /// [ReplyKind.json] 或 [ReplyKind.bytes] 的值。
  Object? get value => switch (kind) {
        ReplyKind.json => jsonDecode(utf8.decode(body)),
        ReplyKind.bytes => body,
        ReplyKind.error || ReplyKind.cancelled => throw StateError('$kind 回复没有值'),
      };

  String get errorMessage => utf8.decode(body);
}
