# App 图标

「懒猫阅读」现用图标为 B5「月夜幻想」：橘白猫睡在发光书页上，夜蓝色背景。界面配色沿用现有设计，设置页使用同款 Logo。

## 母图

- `app-icon-master.png`：满版、不透明、无文字、无预制圆角的正式母图。
- `app-icon-foreground-master.png`：同构图的透明前景，保留猫、书和三颗星，用于 Android 自适应图标。
- 两份母图均保留内置 image_gen 的原生输出 **1254×1254**，没有放大冒充 2048 原图。生成提示词见 `icon-generation-prompts.txt`。
- `app-icon-preview.png` 是本次导出检查图，从左到右为 iOS 圆角预览、macOS、Android 圆形和圆角方形遮罩模拟；不是设备截图。

## 一键生成

在仓库根目录运行（需要 ImageMagick、Dart 和 Python 3）：

```bash
app/tool/generate-icons.sh
```

脚本先从母图导出下列文件，再在 `app/` 中运行 `dart run flutter_launcher_icons`，生成 Android、iOS、macOS 的各尺寸资源。

| 文件 | 尺寸 | 用途 |
|---|---|---|
| `app-icon.png` | 1024×1024 | iOS 和普通 Android 图标；不透明满版，系统负责圆角/遮罩 |
| `app-icon-foreground.png` | 1024×1024 | Android 自适应图标透明前景；配置为每边 20% inset，配 `#202660` 夜蓝背景 |
| `app-icon-macos.png` | 1024×1024 | macOS；824×824 圆角主体，四边各留 100px 透明边 |
| `../app/assets/images/lazy-cat-logo.png` | 256×256 | 设置页 Logo，由组件裁成圆角 |

平台配置在 `app/pubspec.yaml`。修改母图后重新运行脚本即可；不要直接编辑自动生成的各尺寸文件。

`flutter_launcher_icons` 0.14.4 会把 Xcode 工程里的 `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS` 错改成 `AppIcon`。脚本在退出时仅恢复该字段运行前的值，保留其他工程改动，不使用整文件 Git 还原。
