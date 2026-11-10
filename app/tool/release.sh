#!/bin/bash
# 打 Android、iOS 两个平台的发布包（openspec release，prepare-release 设计 D5）。macOS 只用于本地开发调试，不发布。
#   tool/release.sh                      打包并检查产物，不上传：发布前试打
#   tool/release.sh --upload <说明文件>   先做发布前检查，通过后打包、检查产物，建 GitHub 草稿 Release
# 产物放在 build/release/<版本>/ 下。草稿由维护者在 GitHub 上检查后再发布。
set -euo pipefail

# release 密钥的证书指纹（prepare-release 任务 3.1）：APK 不是这把密钥签的就不发布
readonly CERT_SHA256=d2a5aa109c3bbdcde3751bfa290ba95879103c7494deb2efbaad46bf02216a47
readonly APK_LIMIT=20000000

fail() { echo "✗ $*" >&2; exit 1; }
ok() { echo "✓ $*"; }
# 按 1000 进位，和 Flutter 构建输出的大小一致（PRD 里的数字也取自那里）
mb() { echo "$(($1 / 1000000)).$(($1 / 100000 % 10))MB"; }

upload=
if [[ ${1:-} == --upload ]]; then
  [[ -f ${2:-} ]] || fail "用法：tool/release.sh --upload <说明文件>（文件要存在）"
  upload=1
  notes=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
fi
cd "$(dirname "$0")/.."

full=$(sed -n 's/^version: //p' pubspec.yaml)
[[ $full == *+* ]] || fail "pubspec 的版本要写成 <版本>+<构建号>，现在是 $full"
version=${full%+*}
build=${full#*+}
tag=v$version

if [[ -n $upload ]]; then
  [[ -z $(git status --porcelain) ]] || fail "工作区有未提交的改动，先提交"
  git fetch -q --tags origin
  git merge-base --is-ancestor HEAD origin/main || fail "HEAD 还没推送到 origin/main，先推送"
  git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null && fail "tag $tag 已经存在，先改版本号"
  # 草稿 Release 在发布之前不建 tag，要单独查
  gh release view "$tag" >/dev/null 2>&1 && fail "Release $tag 已经存在（可能是草稿），先改版本号"
  previous=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)
  if [[ -n $previous ]]; then
    previous_build=$(git show "$previous:app/pubspec.yaml" | sed -n 's/^version: .*+//p')
    ((build > previous_build)) || fail "构建号 $build 要比上一个版本 $previous 的 $previous_build 大"
  fi
  gh auth status >/dev/null 2>&1 || fail "gh 没有登录"
  ok "发布前检查：${tag}，构建号 ${build}，提交 $(git rev-parse --short HEAD)"
fi

out=$PWD/build/release/$version
apk=$out/novel-reader-$version-android-arm64.apk
ipa=$out/novel-reader-$version-ios-unsigned.ipa
rm -rf "$out"
mkdir -p "$out"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

# Android：只出 arm64-v8a（不支持 32 位 ARM）
flutter build apk --release --split-per-abi --target-platform android-arm64
cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk "$apk"
apksigner=$(ls -d "${ANDROID_HOME:-$HOME/Library/Android/sdk}"/build-tools/* | sort -V | tail -1)/apksigner
digest=$("$apksigner" verify --print-certs "$apk" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p')
[[ $digest == "$CERT_SHA256" ]] || fail "APK 不是 release 密钥签的（证书 SHA-256 是 ${digest}），检查 android/key.properties"
abis=$(unzip -Z1 "$apk" 'lib/*' | cut -d/ -f2 | sort -u | xargs)
[[ $abis == arm64-v8a ]] || fail "APK 里的 ABI 应该只有 arm64-v8a，现在是：$abis"
size=$(stat -f%z "$apk")
((size <= APK_LIMIT)) || fail "APK 是 $(mb "$size")，超过 $(mb "$APK_LIMIT") 的上限"
ok "APK：release 密钥签名，只有 arm64-v8a，$(mb "$size")"

# iOS：未签名的 IPA，用户自签。ditto 打包，保留 framework 里的符号链接
flutter build ios --release --no-codesign
mkdir "$stage/Payload"
ditto build/ios/iphoneos/Runner.app "$stage/Payload/Runner.app"
ditto -c -k --keepParent "$stage/Payload" "$ipa"
unzip -p "$ipa" Payload/Runner.app/Runner >"$stage/Runner"
[[ $(lipo -archs "$stage/Runner") == arm64 ]] || fail "IPA 的可执行文件不是 arm64"
unzip -Z1 "$ipa" | grep -q '^Payload/Runner.app/Frameworks/quickjs_ng_ffi.framework/' || fail "IPA 里没有 quickjs_ng_ffi.framework"
ipa_version=$(unzip -p "$ipa" Payload/Runner.app/Info.plist | plutil -extract CFBundleShortVersionString raw -)
[[ $ipa_version == "$version" ]] || fail "IPA 的版本是 ${ipa_version}，应该是 $version"
ok "IPA：arm64，含 quickjs，版本 ${ipa_version}，$(mb "$(stat -f%z "$ipa")")"

if [[ -n $upload ]]; then
  gh release create "$tag" --draft --target "$(git rev-parse HEAD)" --title "懒猫阅读 $version" --notes-file "$notes" "$apk" "$ipa"
else
  echo "产物在 ${out}（没有上传；发布用 --upload <说明文件>）"
fi
