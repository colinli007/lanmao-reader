## Why

规则引擎和 JS 运行时已经能跑通 A、B、C 类书源的搜索、详情、目录、正文四条链路，但只存在于 spike 和测试里，还没有一个能用的 app。后面要做的登录、验证码、WebView 书源、发现页都要挂在界面上；书源级状态（缓存、书源变量、登录信息）和 Cookie 也只在内存里，重启就丢。现在先做 app 外壳和存储层，让引擎第一次变成可用的阅读器，后续功能有地方接入。

## What Changes

- 新建 Flutter app（仓库根目录 `app/`，社区版），本次支持 iOS 和 macOS；界面用 Material 3 默认组件和主题。
- 书源管理：从文件、网址、粘贴的文本导入 Legado 书源（单个或数组），导入前显示新增、更新、跳过的数目和原因；列表、搜索、启用和停用、删除、导出到剪贴板；书源日志页显示书源 JS 的调试日志。
- 搜索：在所有启用的书源上并发搜索，结果逐步出现，同名同作者的书合并为一项；可以停止，换搜索词时取消上一次；显示失败的书源和原因。
- 详情与目录：从搜索结果进入详情页（封面、作者、分类、简介、最新章节），目录页列出全部章节，可以加入书架、从任一章开始阅读。
- 书架：列出加入的书，按最近阅读排序，显示最新章节和未读章节数；下拉刷新时更新目录；移出书架。
- 阅读：一次显示一章，上下滚动；上一章、下一章、目录跳转；字号、行距、主题（亮、暗、护眼）可调并保存；记住每本书读到哪一章、章内哪个位置；正文缓存到本地，预加载下一章。
- 存储层：书源、书架、目录、正文缓存、阅读进度和设置落盘；rule_engine 的书源级状态（`SourceStore`）和持久 Cookie 落盘，重启后仍在。
- rule_engine 增加 Cookie 的载入和变更通知，供存储层落盘；不改变 Cookie 的匹配和合并语义。
- 分页排版（标点避头尾、翻页动画）、Android、store flavor 不在本次范围（见 design 的 Non-Goals）。

## Capabilities

### New Capabilities
- `app-storage`: 本地存储：哪些数据落盘、重启后怎样恢复、书源级状态和 Cookie 怎样和引擎的内存接口保持一致。
- `source-management`: 书源的导入、列表、启用与停用、删除、导出，以及书源日志。
- `book-search`: 多书源并发搜索、结果合并与排序、取消、失败的书源。
- `book-detail`: 详情页、目录页，从详情加入书架和开始阅读。
- `bookshelf`: 书架列表、排序、未读章节数、更新目录、移出书架。
- `reader`: 滚动阅读：正文的加载与缓存、正文排版、章节切换、阅读设置、阅读进度。

### Modified Capabilities
（无。Cookie 的载入和变更通知是 rule_engine 的接口改动，不改变 `source-request` 里 Cookie 的行为要求。）

## Impact

- 代码：新增 `app/`（Flutter 项目，iOS、macOS）；`packages/rule_engine` 的 `host/cookie_store.dart`、`host/rule_host.dart` 增加 Cookie 的初始值和变更回调。
- 依赖：`drift`（SQLite，含 Flutter 端的 sqlite3 原生库）、`flutter_riverpod`、`file_selector`（官方包，打开书源文件）、`path_provider`；开发依赖 `drift_dev`、`build_runner`。具体版本在实现时按稳定性门槛选定并锁定。
- 平台配置：macOS 沙盒的网络客户端和「用户选择的文件」读权限；iOS 不需要额外权限（网络走 `dart:io`，不受 ATS 限制，spike 已经在 iOS 模拟器上验证过 HTTP 请求）。
- 测试：存储层、搜索合并、正文排版、阅读进度用单元测试；四条链路的界面流程用 widget 测试加回放环境（不联网）；macOS 和 iOS 模拟器上手动走一遍真实书源。真机测试按约定推迟到所有功能完成后。
- 文档：README 的目录表和运行说明；选型文档的进度。
