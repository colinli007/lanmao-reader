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
// 把 *is_error 置 1 表示抛出异常，此时返回值是错误消息；置 2 表示抛出不可捕获的异常，
// 它和中止一样穿过 JS 的 try/catch，一直到最外层求值。
typedef char *(*QjsHostCallback)(int32_t fn_id, const char *args_json, int32_t *is_error);

// memory_limit_bytes <= 0 表示不限制。
FFI_PLUGIN_EXPORT QjsEngine *qjs_new(QjsHostCallback callback, int64_t memory_limit_bytes);

FFI_PLUGIN_EXPORT void qjs_free(QjsEngine *engine);

// 按路径注册宿主函数，如 "java.ajax"，中间对象不存在时自动创建。成功返回 0。
FFI_PLUGIN_EXPORT int32_t qjs_register(QjsEngine *engine, const char *path, int32_t fn_id);

// 把 JSON 值挂到全局变量上，用于注入 result、baseUrl 等上下文。
// 成功返回 NULL，失败返回错误消息（用 qjs_free_string 释放）。
FFI_PLUGIN_EXPORT char *qjs_set_global(QjsEngine *engine, const char *name, const char *json);

// 求值。返回结果的 JSON（undefined 或不可序列化的值返回 NULL）。全局变量 __qjs 上设置了 replacer 函数时，
// 序列化结果和宿主函数的实参都用它作为 JSON.stringify 的 replacer。
// 出错时 *is_error 置 1（不可捕获的异常，包括中止，置 2），返回错误消息。返回的字符串用 qjs_free_string 释放。
// timeout_ms <= 0 表示不限时。abort_flag 可为 NULL；指向的值被其它线程置为非 0 时中止求值，
// 宿主函数返回时也会检查它，所以中止能穿过宿主函数边界，JS 的 try/catch 拦不住。
// 嵌套调用沿用最外层的截止时间和中止标志。
FFI_PLUGIN_EXPORT char *qjs_eval(QjsEngine *engine, const char *code, const char *filename,
                                 int32_t timeout_ms, const int32_t *abort_flag, int32_t *is_error);

FFI_PLUGIN_EXPORT void qjs_free_string(char *str);

// 隔离作用域求值。
//
// 变量层是 JS 里的一个普通对象，代码在非严格模式下以 `with (变量层) { eval(代码) }` 执行（直接 eval），
// 顶层 this 是变量层：var、函数声明、let/const 留在这次调用里，未声明的赋值在求值结束后（包括出错、超时和中止）从全局对象移到变量层上。
// 新建的变量层用完就释放，等于什么都不泄漏；多次求值用同一个变量层时，层上的属性在它们之间保留。
//
// 创建变量层，返回编号（大于 0）。
FFI_PLUGIN_EXPORT int32_t qjs_layer_new(QjsEngine *engine);

FFI_PLUGIN_EXPORT void qjs_layer_free(QjsEngine *engine, int32_t layer_id);

// 在变量层 layer_id 上求值。vars_json 是对象的 JSON（可为 NULL），求值前逐个写到变量层上；
// 全局变量 __qjs 上设置了 revive 函数时，先用它转换这个对象。
// lib_id 不为 0 时，jsLib 的顶层名字对代码可见（见 qjs_lib_new）。
// 返回值、错误、超时和中止的约定与 qjs_eval 相同。
FFI_PLUGIN_EXPORT char *qjs_eval_scoped(QjsEngine *engine, int32_t layer_id, int32_t lib_id, const char *vars_json,
                                        const char *code, int32_t timeout_ms, const int32_t *abort_flag,
                                        int32_t *is_error);

// 在同一个运行时里新建一个 JSContext（独立的 realm），把 code 当作全局脚本执行一次，
// 然后禁止扩展它的全局对象。脚本新增的全局名字经过一个只读的 Proxy 挂到变量层的原型上：
// 读到的是 jsLib 的当前值，赋值只在本次的变量层上新建同名属性（遮蔽，不修改 jsLib）。
// 成功返回编号（大于 0）；失败返回 0，*error 写入错误消息（用 qjs_free_string 释放），
// *is_error 的取值与 qjs_eval 相同。超时和中止的约定与 qjs_eval 相同。
FFI_PLUGIN_EXPORT int32_t qjs_lib_new(QjsEngine *engine, const char *code, const char *filename, int32_t timeout_ms,
                                      const int32_t *abort_flag, char **error, int32_t *is_error);

// 释放 jsLib。之后用这个编号求值以错误结束。
FFI_PLUGIN_EXPORT void qjs_lib_free(QjsEngine *engine, int32_t lib_id);

// 正则：直接调用 libregexp，和 JS 求值无关，但内存分配和中止检查用同一个引擎。
// 编译 UTF-8 的 pattern，flags 是 libregexp.h 里 LRE_FLAG_* 的组合（不含 g、y）。
// 成功返回字节码（用 qjs_regexp_free 释放），*capture_count 写入分组数（含第 0 组），
// 有命名分组时 *group_names 写入以逗号连接的组名（未命名的组为空，用 qjs_free_string 释放），否则为 NULL。
// 失败返回 NULL，*error 写入失败原因（用 qjs_free_string 释放）。
FFI_PLUGIN_EXPORT uint8_t *qjs_regexp_compile(QjsEngine *engine, const char *pattern, int32_t flags,
                                              int32_t *capture_count, char **group_names, char **error);

// 在 UTF-16 串 input[0, len) 里从 start 开始查找下一个匹配。
// 返回 1 表示匹配，0 表示没有匹配，-1 表示被中止，-2 表示内存不足等内部错误。
// 匹配时 captures（长度为分组数的 2 倍）写入每组的起止下标，未参与匹配的组为 -1。
// abort_flag 的含义和 qjs_eval 相同；在求值内部调用时沿用外层的中止标志。
FFI_PLUGIN_EXPORT int32_t qjs_regexp_exec(QjsEngine *engine, const uint8_t *bytecode, const uint16_t *input,
                                          int32_t len, int32_t start, const int32_t *abort_flag,
                                          int32_t *captures);

FFI_PLUGIN_EXPORT void qjs_regexp_free(QjsEngine *engine, uint8_t *bytecode);

#endif
