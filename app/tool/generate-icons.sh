#!/bin/bash
# 从 B5 母图导出输入文件，再生成 Android、iOS、macOS 图标。
set -euo pipefail
cd "$(dirname "$0")/.."

command -v magick >/dev/null
command -v dart >/dev/null
command -v python3 >/dev/null

magick ../design/app-icon-master.png -resize 1024x1024 -alpha off -strip \
  PNG24:../design/app-icon.png
magick ../design/app-icon-foreground-master.png -resize 1024x1024 -strip \
  PNG32:../design/app-icon-foreground.png

# macOS 的图标主体为 824px，外围各留 100px 透明边。
magick ../design/app-icon-master.png -resize 824x824 \
  \( -size 824x824 xc:black -fill white -draw 'roundrectangle 0,0 823,823 184,184' \) \
  -alpha off -compose CopyOpacity -composite \
  -compose Over -background none -gravity center -extent 1024x1024 -strip \
  PNG32:../design/app-icon-macos.png

mkdir -p assets/images
magick ../design/app-icon-master.png -resize 256x256 -alpha off -strip \
  PNG24:assets/images/lazy-cat-logo.png

# 0.14.4 会误改这个 Xcode 设置；只恢复该字段，保留其余工程改动。
icon_project_backup=$(mktemp)
cp ios/Runner.xcodeproj/project.pbxproj "$icon_project_backup"
restore_icon_setting() {
  python3 - "$icon_project_backup" ios/Runner.xcodeproj/project.pbxproj <<'PY'
import re
import sys
from pathlib import Path

before = Path(sys.argv[1]).read_text()
project = Path(sys.argv[2])
after = project.read_text()
pattern = r'ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = [^;]+;'
original = re.findall(pattern, before)
if len(original) != len(re.findall(pattern, after)):
    raise SystemExit('Xcode 图标设置数量改变，请检查 project.pbxproj')
values = iter(original)
restored = re.sub(pattern, lambda _: next(values), after)
if restored != after:
    project.write_text(restored)
PY
  rm -f "$icon_project_backup"
}
trap restore_icon_setting EXIT

dart run flutter_launcher_icons
