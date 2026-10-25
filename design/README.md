# app 图标

`app-icon.svg` 是唯一的源文件：一本翻开的书，透明底。下面三张 1024×1024 的 PNG 都从它渲染，再由 `app/pubspec.yaml` 里 `flutter_launcher_icons` 的配置生成三个平台各尺寸的图标。

| 文件 | 用途 |
|---|---|
| `app-icon.png` | iOS 和 Android 旧版图标：满版深绿底，系统自己加圆角或遮罩；没有透明通道 |
| `app-icon-macos.png` | macOS：圆角方块，四周留透明边（按 Apple 的图标网格，主体 824×824） |
| `app-icon-foreground.png` | Android adaptive icon 的前景：透明底；工具生成时四周再加 16% 的内边距，书最终约占 56%，四角在安全圆里；背景是纯色 `#2F5D50` |

改了 SVG 之后，在本目录下重新渲染，再到 `app/` 下运行 `dart run flutter_launcher_icons`。flutter_launcher_icons 0.14.4 每次运行都会把 `ios/Runner.xcodeproj/project.pbxproj` 里的 `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS` 从 `YES` 错改成 `AppIcon`，运行完用 `git checkout ios/Runner.xcodeproj/project.pbxproj` 还原。

```bash
magick -size 1024x1024 xc:'#2F5D50' \( -background none app-icon.svg -resize 72% \) -gravity center -composite -alpha off app-icon.png
magick -size 1024x1024 xc:none -fill '#2F5D50' -draw 'roundrectangle 100,100 923,923 185,185' \
  \( -background none app-icon.svg -resize 58% \) -gravity center -composite app-icon-macos.png
magick -size 1024x1024 xc:none \( -background none app-icon.svg -resize 82% \) -gravity center -composite app-icon-foreground.png
```
