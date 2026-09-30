// CocoaPods 只编译 Classes 目录，这里把 ../src 下的源文件逐个引入，保证与 Android 的 CMake 列表一致。
// 每个 .c 必须是独立的编译单元（QuickJS 各文件有同名的 static 符号），所以拆成多个文件。
#include "../../src/quickjs_ng_ffi.c"
