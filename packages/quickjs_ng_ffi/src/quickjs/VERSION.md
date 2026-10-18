quickjs-ng v0.17.0 (2026-09-18)
https://github.com/quickjs-ng/quickjs/releases/tag/v0.17.0
只拷贝了库本体（dtoa / libregexp / libunicode / quickjs），不含 quickjs-libc。升级时整体替换本目录。

## 本地补丁

升级后要重新打上，并跑 `test/js_engine_test.dart` 的「隔离求值」组确认。

- `has_with_scope`（quickjs.c）：直接 eval 的代码里，外层函数的 `with` 对象是 eval 函数的闭包变量（`_with_`），原实现只看自己和父函数的作用域，看不到它们，于是 `with (o) { eval('f()') }` 里的 `f()` 不按方法调用，`this` 不是 `o`。补丁在 eval 函数的闭包变量里也找 `_with_`。隔离求值（`qjs_eval_scoped`）靠它让 jsLib 函数的 `this` 是变量层。
