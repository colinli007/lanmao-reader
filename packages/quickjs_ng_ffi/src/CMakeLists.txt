# Android 用这份 CMake 构建；iOS / macOS 走 podspec，源文件列表保持一致。

cmake_minimum_required(VERSION 3.10)

project(quickjs_ng_ffi_library VERSION 0.0.1 LANGUAGES C)

add_library(quickjs_ng_ffi SHARED
  "quickjs_ng_ffi.c"
  "quickjs/quickjs.c"
  "quickjs/libregexp.c"
  "quickjs/libunicode.c"
  "quickjs/dtoa.c"
)

set_target_properties(quickjs_ng_ffi PROPERTIES
  PUBLIC_HEADER quickjs_ng_ffi.h
  OUTPUT_NAME "quickjs_ng_ffi"
  C_STANDARD 11
)

target_compile_definitions(quickjs_ng_ffi PRIVATE DART_SHARED_LIB _GNU_SOURCE)
target_compile_options(quickjs_ng_ffi PRIVATE -O2 -w)

if (ANDROID)
  # Android 15 起支持 16 KB 页大小
  target_link_options(quickjs_ng_ffi PRIVATE "-Wl,-z,max-page-size=16384")
  target_link_libraries(quickjs_ng_ffi m)
endif()
