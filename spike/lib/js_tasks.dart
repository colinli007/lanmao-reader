/// worker 里执行书源 JS 的任务：每个 worker 一个 QuickJS 引擎，`java.*` 宿主函数接到阻塞桥上。
///
/// 任务闭包要发到 worker，它捕获的变量必须能跨 isolate 传递；Dart 闭包会捕获整个外层上下文，
/// 所以任务都由这里的顶层函数构造。
library;

import 'package:blocking_bridge/blocking_bridge.dart';
import 'package:quickjs_ng_ffi/quickjs_ng_ffi.dart';

/// 需要主 isolate 异步完成的宿主请求。
enum HostOp { httpGet, verificationCode }

/// isolate 级变量：每个 worker 一个引擎，跨任务复用。宿主函数只注册一次，
/// 所以通过 [WorkerContext.current] 取当前任务，而不是捕获某个任务。
final JsEngine _engine = _createEngine();

/// `java.log` 写入的记录，留在 worker 里，供后续任务读出。
final List<Object?> _logs = [];

JsEngine _createEngine() {
  final engine = JsEngine();
  engine.register('java.ajax', (args) => WorkerContext.current.callHost(HostOp.httpGet.name, args));
  engine.register(
    'java.getVerificationCode',
    (args) => WorkerContext.current.callHost(HostOp.verificationCode.name, args),
  );
  // 纯计算的宿主函数在 worker 里同步完成，不经过主 isolate
  engine.register('java.getString', (args) {
    final rule = args[0] as String;
    const jsPrefix = '@js:';
    if (!rule.startsWith(jsPrefix)) return rule;
    return engine.eval(rule.substring(jsPrefix.length));
  });
  // 验证用：一段不检查中止信号的 Dart 计算，模拟规则引擎在宿主函数里卡住（例如正则灾难性回溯）
  engine.register('java.spin', (args) {
    final watch = Stopwatch()..start();
    while (watch.elapsedMilliseconds < (args[0] as int)) {}
    return null;
  });
  engine.register('java.log', (args) {
    _logs.add(args.first);
    return null;
  });
  return engine;
}

/// 注入 [globals] 后执行 [code]，任务取消或超时时 JS 被中止。
Object? Function() evalJs(String code, {Map<String, Object?> globals = const {}}) => () {
      globals.forEach(_engine.setGlobal);
      return _engine.eval(code, abortSignal: WorkerContext.current.abortSignal);
    };

/// 取出并清空本 worker 上 `java.log` 的记录。
List<Object?> Function() takeLogs() => () {
      final logs = [..._logs];
      _logs.clear();
      return logs;
    };
