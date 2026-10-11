// quickjs-ng 的最小 C 胶水层，供 Dart FFI 调用。
//
// 设计约束：
// - 值跨边界一律用 UTF-8 JSON 字符串传递，C 侧不暴露 JSValue。
// - 宿主函数是同步回调：JS 调用时直接回到 Dart，拿到返回值后继续执行。
// - 一个引擎只能在创建它的 isolate 里使用；Dart isolate 可能换 OS 线程，
//   所以每个最外层入口（注册、设置全局变量、求值）都会按当前线程刷新栈顶。

#ifndef QUICKJS_NG_FFI_H
#define QUICKJS_NG_FFI_H

#include <stdint.h>

#if _WIN32
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

typedef struct QjsEngine QjsEngine;

// 宿主回调。
// fn_id：注册时给的编号；args_json：实参数组的 JSON。
// 返回值：用 malloc 分配的 JSON 字符串（C 侧负责 free），NULL 表示 undefined。
// 把 *is_error 置 1 表示抛出异常，此时返回值是错误消息。
typedef char *(*QjsHostCallback)(int32_t fn_id, const char *args_json, int32_t *is_error);

// memory_limit_bytes <= 0 表示不限制。
FFI_PLUGIN_EXPORT QjsEngine *qjs_new(QjsHostCallback callback, int64_t memory_limit_bytes);

FFI_PLUGIN_EXPORT void qjs_free(QjsEngine *engine);

// 按路径注册宿主函数，如 "java.ajax"，中间对象不存在时自动创建。成功返回 0。
FFI_PLUGIN_EXPORT int32_t qjs_register(QjsEngine *engine, const char *path, int32_t fn_id);

// 把 JSON 值挂到全局变量上，用于注入 result、baseUrl 等上下文。
// 成功返回 NULL，失败返回错误消息（用 qjs_free_string 释放）。
FFI_PLUGIN_EXPORT char *qjs_set_global(QjsEngine *engine, const char *name, const char *json);

// 求值。返回结果的 JSON（undefined 或不可序列化的值返回 NULL）。
// 出错时 *is_error 置 1，返回错误消息。返回的字符串用 qjs_free_string 释放。
// timeout_ms <= 0 表示不限时。abort_flag 可为 NULL；指向的值被其它线程置为非 0 时中止求值，
// 宿主函数返回时也会检查它，所以中止能穿过宿主函数边界，JS 的 try/catch 拦不住。
// 嵌套调用沿用最外层的截止时间和中止标志。
FFI_PLUGIN_EXPORT char *qjs_eval(QjsEngine *engine, const char *code, const char *filename,
                                 int32_t timeout_ms, const int32_t *abort_flag, int32_t *is_error);

FFI_PLUGIN_EXPORT void qjs_free_string(char *str);

#endif
