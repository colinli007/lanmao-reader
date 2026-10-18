part of '../quickjs_ng_ffi.dart';

/// 隔离求值用的变量层（[JsEngine.evalScoped]）。
///
/// 代码在非严格模式下以 `with (变量层) { eval(代码) }` 执行：注入的变量是变量层的属性，顶层 `this` 是变量层；
/// 顶层的 `var`、函数声明和 `let`/`const` 只留在那一次求值里，未声明的赋值在求值结束后从全局移到变量层上。
/// 每次求值用新的变量层就互不影响；多次求值共用一个变量层时，层上的属性（包括未声明的赋值）在它们之间保留。
class JsLayer {
  JsLayer(JsEngine engine) : _engine = engine {
    engine._checkAlive();
    _id = _bindings.qjs_layer_new(engine._engine);
    if (_id == 0) throw JsException('创建变量层失败');
  }

  final JsEngine _engine;
  late final int _id;
  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (!_engine._disposed) _bindings.qjs_layer_free(_engine._engine, _id);
  }

  void _checkOwner(JsEngine engine) {
    if (_disposed) throw StateError('JsLayer 已释放');
    if (!identical(engine, _engine)) throw ArgumentError('JsLayer 不属于这个引擎');
  }
}

/// 共享作用域：在同一个运行时的独立 realm 里把 [code] 当作全局脚本执行一次。
///
/// 隔离求值时传入它，脚本新增的全局名字对代码可见，读到的是当前值；代码给这些名字赋值只遮蔽、不修改；
/// 它里面的函数以 `f()` 形式被调用时 `this` 是本次的变量层。函数体里用的内建对象来自它自己的 realm。
/// 脚本出错时抛出 [JsException]；超时和中止的约定与 [JsEngine.eval] 相同。
class JsLib {
  factory JsLib(
    JsEngine engine,
    String code, {
    Duration? timeout,
    Pointer<Int32>? abortSignal,
    String filename = '<jsLib>',
  }) {
    engine._checkAlive();
    final id = using((arena) {
      final error = arena<Pointer<Char>>();
      final isError = arena<Int32>();
      final id = _bindings.qjs_lib_new(
        engine._engine,
        code.toNativeUtf8(allocator: arena).cast(),
        filename.toNativeUtf8(allocator: arena).cast(),
        timeout?.inMilliseconds ?? 0,
        abortSignal ?? nullptr,
        error,
        isError,
      );
      final message = _takeString(error.value);
      if (id == 0) throw JsException(message ?? 'unknown error', uncatchable: isError.value == 2);
      return id;
    });
    return JsLib._(engine, id);
  }

  JsLib._(this._engine, this._id);

  final JsEngine _engine;
  final int _id;
  bool _disposed = false;

  /// 释放后再用它求值抛出 [StateError]。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (!_engine._disposed) _bindings.qjs_lib_free(_engine._engine, _id);
  }

  void _checkOwner(JsEngine engine) {
    if (_disposed) throw StateError('JsLib 已释放');
    if (!identical(engine, _engine)) throw ArgumentError('JsLib 不属于这个引擎');
  }
}
