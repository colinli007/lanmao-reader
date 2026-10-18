import 'package:blocking_bridge/blocking_bridge.dart';
import 'package:rule_engine/rule_engine.dart';

/// 给用户看的错误原因：类型加消息（引擎的错误自带类型、书源名和字段）。
String describeError(Object error) => switch (error) {
  RuleEngineException() => error.toString(),
  HostCallException(:final message) => '网络错误：$message',
  TaskTimeoutException(:final timeout) => '超时：超过 ${timeout.inSeconds} 秒',
  WorkerExitedException() => 'worker 异常退出',
  _ => error.toString(),
};
