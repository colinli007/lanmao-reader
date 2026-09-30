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

一个 `JsEngine` 只能在创建它的 isolate 里使用。需要等待网络或界面操作的宿主函数，见 `spike/lib/js_worker.dart` 里的阻塞桥。

## 测试

```bash
./tool/build_host.sh
QUICKJS_NG_FFI_LIB=$PWD/build/host/libquickjs_ng_ffi.dylib dart test
```
