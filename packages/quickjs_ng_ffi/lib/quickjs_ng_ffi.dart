/// quickjs-ng 的同步封装：执行书源 JS，JS 可同步调用 Dart 注册的宿主函数。
///
/// 一个 [JsEngine] 只能在创建它的 isolate 里使用。宿主函数在 JS 执行过程中被同步调用，
/// 函数里可以再次调用 [JsEngine.eval]（规则引擎回调 JS 的嵌套场景）。
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'quickjs_ng_ffi_bindings_generated.dart';

part 'src/js_regexp.dart';

/// 宿主函数：实参和返回值都必须能被 JSON 表示。抛出的异常会变成 JS 里的 Error。
typedef HostFunction = Object? Function(List<Object?> args);

class JsException implements Exception {
  JsException(this.message);

  final String message;

  @override
  String toString() => 'JsException: $message';
}

class JsEngine {
  JsEngine({int memoryLimitBytes = 64 * 1024 * 1024}) {
    // 返回指针的回调不能设置 exceptionalReturn；_dispatch 自己捕获全部异常
    _callback = NativeCallable<QjsHostCallbackFunction>.isolateLocal(_dispatch);
    _engine = _bindings.qjs_new(_callback.nativeFunction, memoryLimitBytes);
    if (_engine == nullptr) {
      _callback.close();
      throw StateError('创建 QuickJS 引擎失败');
    }
  }

  late final NativeCallable<QjsHostCallbackFunction> _callback;
  late Pointer<QjsEngine> _engine;
  final List<HostFunction> _functions = [];
  // 正则的字节码由引擎的分配器分配，必须在引擎释放之前释放
  final Set<JsRegExp> _regExps = {};
  bool _disposed = false;

  /// 按路径注册宿主函数，如 `java.ajax`。
  void register(String path, HostFunction function) {
    _checkAlive();
    final fnId = _functions.length;
    _functions.add(function);
    final status = using((arena) {
      return _bindings.qjs_register(_engine, path.toNativeUtf8(allocator: arena).cast(), fnId);
    });
    if (status != 0) throw JsException('注册宿主函数失败：$path');
  }

  /// 把值挂到全局变量上，如 `result`、`baseUrl`。
  void setGlobal(String name, Object? value) {
    _checkAlive();
    final error = using((arena) {
      final result = _bindings.qjs_set_global(
        _engine,
        name.toNativeUtf8(allocator: arena).cast(),
        jsonEncode(value).toNativeUtf8(allocator: arena).cast(),
      );
      if (result == nullptr) return null;
      final message = result.cast<Utf8>().toDartString();
      _bindings.qjs_free_string(result);
      return message;
    });
    if (error != null) throw JsException('设置全局变量 $name 失败：$error');
  }

  /// 执行代码并返回最后一个表达式的值（按 JSON 转成 Dart 对象）。
  ///
  /// [abortSignal] 指向的值被（任意线程）置为非 0 后，JS 被中止并抛出 [JsException]，JS 里的 try/catch 拦不住；
  /// 宿主函数返回时也会检查它，所以宿主函数吞掉内层的中止也没用。
  /// 嵌套调用时 [timeout] 和 [abortSignal] 只在最外层生效。
  Object? eval(String code, {Duration? timeout, Pointer<Int32>? abortSignal, String filename = '<eval>'}) {
    _checkAlive();
    return using((arena) {
      final isError = arena<Int32>();
      final result = _bindings.qjs_eval(
        _engine,
        code.toNativeUtf8(allocator: arena).cast(),
        filename.toNativeUtf8(allocator: arena).cast(),
        timeout?.inMilliseconds ?? 0,
        abortSignal ?? nullptr,
        isError,
      );
      final text = result == nullptr ? null : result.cast<Utf8>().toDartString();
      _bindings.qjs_free_string(result);
      if (isError.value != 0) throw JsException(text ?? 'unknown error');
      return text == null ? null : jsonDecode(text);
    });
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final regExp in _regExps.toList()) {
      regExp.dispose();
    }
    _bindings.qjs_free(_engine);
    _engine = nullptr;
    _callback.close();
  }

  Pointer<Char> _dispatch(int fnId, Pointer<Char> argsJson, Pointer<Int32> isError) {
    try {
      final args = jsonDecode(argsJson.cast<Utf8>().toDartString()) as List<Object?>;
      final result = _functions[fnId](args);
      if (result == null) return nullptr;
      // C 侧用 free 释放，所以必须用 C 的 malloc 分配
      return jsonEncode(result).toNativeUtf8(allocator: malloc).cast();
    } catch (e) {
      isError.value = 1;
      final message = e is JsException ? e.message : e.toString();
      return message.toNativeUtf8(allocator: malloc).cast();
    }
  }

  void _checkAlive() {
    if (_disposed) throw StateError('JsEngine 已释放');
  }
}

const String _libName = 'quickjs_ng_ffi';

/// 开发机上跑 `dart test` 时，用环境变量指向 `tool/build_host.sh` 编出来的动态库。
final DynamicLibrary _dylib = () {
  final override = Platform.environment['QUICKJS_NG_FFI_LIB'];
  if (override != null) return DynamicLibrary.open(override);
  if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.open('$_libName.framework/$_libName');
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('lib$_libName.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('$_libName.dll');
  }
  throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
}();

final QuickjsNgFfiBindings _bindings = QuickjsNgFfiBindings(_dylib);
