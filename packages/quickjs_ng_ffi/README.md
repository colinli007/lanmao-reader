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

一个 `JsEngine` 只能在创建它的 isolate 里使用；它不会让 isolate 一直活着，命令行工具用完不 `dispose` 也能退出。需要等待网络或界面操作的宿主函数，用 `packages/blocking_bridge` 的阻塞桥，接法见 `spike/lib/js_tasks.dart`。

`eval` 可以传入外部中止信号 `abortSignal`（共享内存里的一个 `Int32`，任何线程写入非 0 都会中止求值）。中止对 JS 的 `try/catch` 不可见，并且会穿过宿主函数边界：宿主函数返回时如果信号已经设置，调用它的 JS 也会被中止。

## 隔离求值与 jsLib

书源 JS 每次求值都要有自己的作用域，`evalScoped` 在一个变量层上求值：

```dart
final layer = JsLayer(engine);
engine.evalScoped('var x = 1; result.trim()', layer: layer, vars: {'result': ' 三体 '}); // '三体'
layer.dispose();
```

- 代码在非严格模式下以 `with (变量层) { eval(代码) }` 执行（直接 eval），顶层 `this` 是变量层。
- 顶层 `var`、函数声明、`let`/`const` 只留在这次求值里；未声明的赋值在求值结束后（包括出错、超时和中止）从全局移到变量层上。
- 多次求值共用一个变量层时，层上的属性在它们之间保留（目录的 `formatJs` 这样用）。
- 全局变量 `__qjs` 上设置了 `revive` 函数时，`vars` 先经它转换再挂到变量层上（规则引擎用它把句柄标记换成包装对象）；设置了 `replacer` 函数时，求值结果和宿主函数的实参序列化成 JSON 时用它作为 replacer（规则引擎用它表示 NaN、Infinity）。

`JsLib` 是共享作用域：在同一个运行时的独立 realm 里执行一次 jsLib，之后传给 `evalScoped`。jsLib 新增的全局名字对代码可见，读到的是当前值；代码给它们赋值只遮蔽、不修改；jsLib 函数以 `f()` 调用时 `this` 是本次的变量层。

宿主函数抛出 `JsException(message, uncatchable: true)` 时，JS 的 `try/catch` 拦不住，错误一直传到最外层求值（规则引擎用它实现嵌套求值的层数上限）；嵌套求值得到的不可捕获错误原样抛出即可继续向外传。

开销（macOS，Apple M4，`tool/bench_scoped_eval.dart`）：2000 次「新建变量层 + 注入 5 个变量 + `result.trim()`」约 40 ms，挂上 jsLib 时相同；同样 2000 次普通求值约 4 ms。

`src/quickjs/` 打了一个本地补丁（见 `VERSION.md`），升级 quickjs-ng 时要重新打上。

## 正则

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
