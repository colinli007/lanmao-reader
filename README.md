# novel-reader

跨端开源小说阅读器，兼容 Legado（开源阅读 3.0）书源。纯 Flutter 实现。

约束：开源、完全免费、不上架应用市场；书源功能只放在不上架的社区版里。

## 目录

| 路径 | 内容 |
|---|---|
| `app/` | 阅读器 app（社区版，iOS、macOS）：书源管理、搜索、详情与目录、书架、滚动阅读；数据存在本机 SQLite 里。书源相关的代码都在 `app/lib/online/`，书架、阅读器、存储层不依赖规则引擎 |
| `packages/quickjs_ng_ffi` | 执行书源 JS 的引擎：quickjs-ng 源码（固定在 v0.17.0）+ C 胶水层 + ffigen 生成的绑定 + Dart 封装。支持 JS 同步调用宿主函数、嵌套求值、超时和内存上限 |
| `packages/rule_engine` | 书源规则引擎：载入 Legado 书源，解析规则，执行搜索、详情、目录、正文四条链路，书源 JS 在 quickjs-ng 上执行，注入常用宿主 API；行为对齐 legado-with-MD3 |
| `packages/blocking_bridge` | 阻塞桥：worker isolate 池，任务可以同步等待主 isolate 的异步结果，支持截止时间、取消、故障恢复 |
| `packages/native_synchronization` | 从 dart-lang/labs 拷贝进来自己维护的阻塞原语（Mailbox） |
| `spike/` | 纯 Flutter 路线的前置验证 app 和集成测试 |
| `docs/` | 技术选型、复核报告 |

选型依据和验证结果见 [docs/技术选型与验证-2026-09-28.md](docs/技术选型与验证-2026-09-28.md)。

## 运行 app

```bash
cd app
flutter run -d macos            # 或 iOS 模拟器
dart run build_runner build     # 改了 lib/storage/database.dart 的表之后重新生成

# 单元测试和 widget 测试；其中落盘的测试要执行书源 JS，需要开发机上编出来的 quickjs 动态库（见下一节）
QUICKJS_NG_FFI_LIB=$PWD/../packages/quickjs_ng_ffi/build/host/libquickjs_ng_ffi.dylib flutter test

# 端到端集成测试：本地 HTTP 服务器上的假书源，走完导入、搜索、详情、加书架、阅读
flutter test integration_test/app_flow_test.dart -d macos

# 真实书源走查（联网，见文件里的说明）
flutter test integration_test/real_sources_test.dart -d macos --dart-define=WALKTHROUGH_SOURCES=<书源文件网址>
```

## 运行验证

```bash
# 引擎单元测试（开发机，不需要 Flutter 构建）
cd packages/quickjs_ng_ffi
./tool/build_host.sh
QUICKJS_NG_FFI_LIB=$PWD/build/host/libquickjs_ng_ffi.dylib dart test

# 规则引擎单元测试和固定样例回放（开发机，需要上面编出来的 quickjs 动态库）
cd packages/rule_engine
QUICKJS_NG_FFI_LIB=$PWD/../quickjs_ng_ffi/build/host/libquickjs_ng_ffi.dylib dart test

# 阻塞桥单元测试（开发机）
cd packages/blocking_bridge
dart test

# 阻塞桥集成测试（macOS / Android / iOS）
cd spike
flutter test integration_test -d macos
flutter test integration_test -d emulator-5554

# 同一套集成测试的 AOT 构建（真机），另外输出 worker 的内存成本
flutter drive --profile --driver=test_driver/integration_test.dart --target=integration_test/spike_test.dart -d <设备>
```
