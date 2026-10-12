# quickjs_ng_ffi

quickjs-ng 的 Dart FFI 绑定，给书源 JS 用。

- 源码：`src/quickjs/`，固定版本见 `src/quickjs/VERSION.md`；升级时整体替换这个目录，然后重跑测试。
- C 胶水层：`src/quickjs_ng_ffi.{h,c}`。值在两侧之间统一用 JSON 字符串传递，宿主函数是同步回调。
- 绑定：`dart run ffigen --config ffigen.yaml` 生成 `lib/quickjs_ng_ffi_bindings_generated.dart`。
- 构建：Android 走 `src/CMakeLists.txt`；iOS / macOS 走 podspec，`Classes/` 下的文件逐个 include `src/` 里的源文件。

```dart
final engine = JsEngine();
engine.register('java.md5Encode', (args) => md5(args[0] as String));
engine.setGlobal('result', html);
final value = engine.eval('java.md5Encode(result)', timeout: const Duration(seconds: 5));
engine.dispose();
```

一个 `JsEngine` 只能在创建它的 isolate 里使用。需要等待网络或界面操作的宿主函数，用 `packages/blocking_bridge` 的阻塞桥，接法见 `spike/lib/js_tasks.dart`。

`eval` 可以传入外部中止信号 `abortSignal`（共享内存里的一个 `Int32`，任何线程写入非 0 都会中止求值）。中止对 JS 的 `try/catch` 不可见，并且会穿过宿主函数边界：宿主函数返回时如果信号已经设置，调用它的 JS 也会被中止。

`JsRegExp` 用 quickjs-ng 自带的 libregexp 执行正则，语法同 JS `RegExp`，匹配同样接受 `abortSignal`，用来跑书源提供的、可能灾难性回溯的正则。正则属于创建它的引擎，引擎释放时一并释放。

```dart
final regExp = JsRegExp(engine, r'第(\d+)章');
final matches = regExp.allMatches(text, abortSignal: signal); // 中止时抛出 JsException('interrupted')
```

## 测试

```bash
./tool/build_host.sh
QUICKJS_NG_FFI_LIB=$PWD/build/host/libquickjs_ng_ffi.dylib dart test
```
