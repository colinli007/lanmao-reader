#!/bin/sh
# 在开发机上编译一份动态库，供 `dart test` 直接加载（不经过 Flutter 构建）。
set -e
cd "$(dirname "$0")/.."
mkdir -p build/host
case "$(uname)" in
  Darwin) out=build/host/libquickjs_ng_ffi.dylib; shared="-dynamiclib" ;;
  *) out=build/host/libquickjs_ng_ffi.so; shared="-shared -fPIC" ;;
esac
cc $shared -O2 -w -D_GNU_SOURCE -o "$out" \
  src/quickjs_ng_ffi.c src/quickjs/quickjs.c src/quickjs/libregexp.c src/quickjs/libunicode.c src/quickjs/dtoa.c -lm
echo "$out"
