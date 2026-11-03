# lanmao_reader

阅读器 app（社区版，iOS、macOS）：书源管理、多书源搜索、详情与目录、书架、滚动阅读，数据存在本机 SQLite（drift）里。

- `lib/online/`：书源模块，唯一引用 `rule_engine` 的目录（`test/module_boundary_test.dart` 检查）。
- `lib/storage/`：数据库和表，表生成的数据类就是书架和阅读器的模型；改了表之后运行 `dart run build_runner build`。
- `lib/library/`：书架、阅读器取目录和正文的接口（`BookContentSource`）和共用的小件。
- `lib/bookshelf/`、`lib/reader/`：书架和阅读页。

运行和测试的命令见仓库根目录的 README；行为规格见 `openspec/specs/` 下的 app-storage、source-management、book-search、book-detail、bookshelf、reader，设计见 `openspec/changes/archive/2026-10-18-add-app-shell/design.md`。
