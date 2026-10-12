#include "quickjs_ng_ffi.h"

#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "quickjs/libregexp.h"
#include "quickjs/quickjs.h"

struct QjsEngine {
    JSRuntime *rt;
    JSContext *ctx;
    QjsHostCallback callback;
    // 最外层求值的截止时间（毫秒，单调时钟），0 表示不限时
    int64_t deadline_ms;
    // 最外层求值的外部中止标志，非 0 表示中止；由其它线程写入，NULL 表示没有
    const int32_t *abort_flag;
    // 求值嵌套深度：宿主函数里再次求值时大于 1
    int32_t depth;
};

static int64_t now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static bool is_aborted(const QjsEngine *engine) {
    return engine->abort_flag != NULL && __atomic_load_n(engine->abort_flag, __ATOMIC_RELAXED) != 0;
}

static int interrupt_handler(JSRuntime *rt, void *opaque) {
    (void)rt;
    QjsEngine *engine = opaque;
    return is_aborted(engine) || (engine->deadline_ms > 0 && now_ms() > engine->deadline_ms);
}

// 与 QuickJS 自己的中断错误一致：InternalError("interrupted")，并标记为 uncatchable，try/catch 拦不住
static JSValue throw_interrupted(JSContext *ctx) {
    JSValue error = JS_NewInternalError(ctx, "interrupted");
    JS_SetUncatchableError(ctx, error);
    return JS_Throw(ctx, error);
}

// Dart isolate 在两次事件之间可能被调度到另一个 OS 线程，QuickJS 记录的栈顶就失效了，
// 栈溢出检查会误报 "Maximum call stack size exceeded"。所以每个从 Dart 进入的最外层调用都要按当前线程重算栈顶；
// 嵌套调用（宿主函数里再次进入）仍在同一线程上，不需要重算。
static void sync_stack_top(QjsEngine *engine) {
    if (engine->depth == 0) JS_UpdateStackTop(engine->rt);
}

static char *dup_cstring(const char *src, size_t len) {
    char *out = malloc(len + 1);
    if (out == NULL) return NULL;
    memcpy(out, src, len);
    out[len] = '\0';
    return out;
}

static char *dup_literal(const char *src) {
    return dup_cstring(src, strlen(src));
}

// 取出当前异常并格式化为「消息 + 调用栈」，同时清掉异常状态。
static char *take_exception_message(JSContext *ctx) {
    JSValue exception = JS_GetException(ctx);
    size_t len = 0;
    const char *message = JS_ToCStringLen(ctx, &len, exception);
    char *out = NULL;

    if (JS_IsError(exception)) {
        JSValue stack = JS_GetPropertyStr(ctx, exception, "stack");
        const char *stack_str = JS_IsUndefined(stack) ? NULL : JS_ToCString(ctx, stack);
        if (message != NULL && stack_str != NULL && stack_str[0] != '\0') {
            size_t stack_len = strlen(stack_str);
            out = malloc(len + 1 + stack_len + 1);
            if (out != NULL) {
                memcpy(out, message, len);
                out[len] = '\n';
                memcpy(out + len + 1, stack_str, stack_len + 1);
            }
        }
        if (stack_str != NULL) JS_FreeCString(ctx, stack_str);
        JS_FreeValue(ctx, stack);
    }
    if (out == NULL) {
        out = message != NULL ? dup_cstring(message, len) : dup_literal("unknown error");
    }
    if (message != NULL) JS_FreeCString(ctx, message);
    JS_FreeValue(ctx, exception);
    return out;
}

// 把 JS 值序列化成 JSON；undefined、函数等不可序列化的值返回 NULL。
static char *to_json(JSContext *ctx, JSValueConst value, int32_t *is_error) {
    if (JS_IsUndefined(value)) return NULL;
    JSValue json = JS_JSONStringify(ctx, value, JS_UNDEFINED, JS_UNDEFINED);
    if (JS_IsException(json)) {
        *is_error = 1;
        return take_exception_message(ctx);
    }
    char *out = NULL;
    if (!JS_IsUndefined(json)) {
        size_t len = 0;
        const char *str = JS_ToCStringLen(ctx, &len, json);
        if (str != NULL) {
            out = dup_cstring(str, len);
            JS_FreeCString(ctx, str);
        }
    }
    JS_FreeValue(ctx, json);
    return out;
}

static JSValue host_function(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv,
                             int magic, JSValueConst *func_data) {
    (void)this_val;
    (void)func_data;
    QjsEngine *engine = JS_GetContextOpaque(ctx);

    JSValue args = JS_NewArray(ctx);
    for (int i = 0; i < argc; i++) {
        JS_SetPropertyUint32(ctx, args, (uint32_t)i, JS_DupValue(ctx, argv[i]));
    }
    int32_t is_error = 0;
    char *args_json = to_json(ctx, args, &is_error);
    JS_FreeValue(ctx, args);
    if (is_error) {
        JSValue error = JS_ThrowPlainError(ctx, "宿主函数参数无法序列化：%s", args_json);
        free(args_json);
        return error;
    }

    char *result = engine->callback(magic, args_json != NULL ? args_json : "[]", &is_error);
    free(args_json);

    // 中止信号在宿主函数执行期间被设置时，不管它正常返回还是报错（报错可能就是内层被中止、或被唤醒的取消），
    // 都不能把结果交回 JS：否则外层 JS 能 catch 住，或者宿主函数吞掉中止后 JS 继续执行
    if (is_aborted(engine)) {
        free(result);
        return throw_interrupted(ctx);
    }
    if (is_error) {
        JSValue error = JS_ThrowPlainError(ctx, "%s", result != NULL ? result : "host error");
        free(result);
        return error;
    }
    if (result == NULL) return JS_UNDEFINED;

    JSValue value = JS_ParseJSON(ctx, result, strlen(result), "<host>");
    free(result);
    return value;
}

QjsEngine *qjs_new(QjsHostCallback callback, int64_t memory_limit_bytes) {
    QjsEngine *engine = calloc(1, sizeof(QjsEngine));
    if (engine == NULL) return NULL;
    engine->rt = JS_NewRuntime();
    if (engine->rt == NULL) {
        free(engine);
        return NULL;
    }
    engine->ctx = JS_NewContext(engine->rt);
    if (engine->ctx == NULL) {
        JS_FreeRuntime(engine->rt);
        free(engine);
        return NULL;
    }
    engine->callback = callback;
    if (memory_limit_bytes > 0) JS_SetMemoryLimit(engine->rt, (size_t)memory_limit_bytes);
    JS_SetContextOpaque(engine->ctx, engine);
    JS_SetInterruptHandler(engine->rt, interrupt_handler, engine);
    return engine;
}

void qjs_free(QjsEngine *engine) {
    if (engine == NULL) return;
    JS_FreeContext(engine->ctx);
    JS_FreeRuntime(engine->rt);
    free(engine);
}

int32_t qjs_register(QjsEngine *engine, const char *path, int32_t fn_id) {
    sync_stack_top(engine);
    JSContext *ctx = engine->ctx;
    JSValue target = JS_GetGlobalObject(ctx);
    const char *segment = path;

    for (const char *dot = strchr(segment, '.'); dot != NULL; dot = strchr(segment, '.')) {
        char *name = dup_cstring(segment, (size_t)(dot - segment));
        JSValue next = JS_GetPropertyStr(ctx, target, name);
        if (!JS_IsObject(next)) {
            JS_FreeValue(ctx, next);
            next = JS_NewObject(ctx);
            JS_SetPropertyStr(ctx, target, name, JS_DupValue(ctx, next));
        }
        free(name);
        JS_FreeValue(ctx, target);
        target = next;
        segment = dot + 1;
    }

    JSValue fn = JS_NewCFunctionData2(ctx, host_function, segment, 0, fn_id, 0, NULL);
    int status = JS_SetPropertyStr(ctx, target, segment, fn);
    JS_FreeValue(ctx, target);
    return status < 0 ? -1 : 0;
}

char *qjs_set_global(QjsEngine *engine, const char *name, const char *json) {
    sync_stack_top(engine);
    JSContext *ctx = engine->ctx;
    JSValue value = JS_ParseJSON(ctx, json, strlen(json), "<global>");
    if (JS_IsException(value)) return take_exception_message(ctx);
    JSValue global = JS_GetGlobalObject(ctx);
    int status = JS_SetPropertyStr(ctx, global, name, value);
    JS_FreeValue(ctx, global);
    return status < 0 ? take_exception_message(ctx) : NULL;
}

char *qjs_eval(QjsEngine *engine, const char *code, const char *filename, int32_t timeout_ms,
               const int32_t *abort_flag, int32_t *is_error) {
    JSContext *ctx = engine->ctx;
    *is_error = 0;

    bool is_outermost = engine->depth == 0;
    sync_stack_top(engine);
    if (is_outermost) {
        engine->deadline_ms = timeout_ms > 0 ? now_ms() + timeout_ms : 0;
        engine->abort_flag = abort_flag;
    }
    engine->depth++;

    // 中断回调只在循环回边和函数调用处轮询，没有循环的代码可能一次都不检查，所以先查一次
    JSValue value = is_outermost && is_aborted(engine)
                        ? throw_interrupted(ctx)
                        : JS_Eval(ctx, code, strlen(code), filename, JS_EVAL_TYPE_GLOBAL);
    char *out;
    if (JS_IsException(value)) {
        *is_error = 1;
        out = take_exception_message(ctx);
    } else {
        out = to_json(ctx, value, is_error);
    }
    JS_FreeValue(ctx, value);

    engine->depth--;
    if (is_outermost) {
        engine->deadline_ms = 0;
        engine->abort_flag = NULL;
    }
    return out;
}

void qjs_free_string(char *str) {
    free(str);
}

// lre_compile 和 lre_exec 把 ctx 作为 opaque 交给 lre_realloc、lre_check_stack_overflow、lre_check_timeout，
// 后者最终调用引擎的 interrupt_handler，所以中止标志的设置方式和 qjs_eval 一样
uint8_t *qjs_regexp_compile(QjsEngine *engine, const char *pattern, int32_t flags, int32_t *capture_count,
                            char **group_names, char **error) {
    *group_names = NULL;
    *error = NULL;
    sync_stack_top(engine);
    char error_msg[64];
    int bytecode_len = 0;
    uint8_t *bytecode = lre_compile(&bytecode_len, error_msg, sizeof(error_msg), pattern, strlen(pattern),
                                    flags, engine->ctx);
    if (bytecode == NULL) {
        *error = dup_literal(error_msg);
        return NULL;
    }
    *capture_count = lre_get_capture_count(bytecode);

    // 组名依次存放，每个后面跟 LRE_GROUP_NAME_TRAILER_LEN 字节（含结尾的 '\0'），未命名的组为空串
    const char *names = lre_get_groupnames(bytecode);
    if (names != NULL) {
        size_t total = 0;
        const char *p = names;
        for (int i = 1; i < *capture_count; i++) {
            size_t len = strlen(p);
            total += len + 1;
            p += len + LRE_GROUP_NAME_TRAILER_LEN;
        }
        char *out = malloc(total + 1);
        if (out != NULL) {
            char *q = out;
            p = names;
            for (int i = 1; i < *capture_count; i++) {
                size_t len = strlen(p);
                if (i > 1) *q++ = ',';
                memcpy(q, p, len);
                q += len;
                p += len + LRE_GROUP_NAME_TRAILER_LEN;
            }
            *q = '\0';
        }
        *group_names = out;
    }
    return bytecode;
}

int32_t qjs_regexp_exec(QjsEngine *engine, const uint8_t *bytecode, const uint16_t *input, int32_t len,
                        int32_t start, const int32_t *abort_flag, int32_t *captures) {
    bool is_outermost = engine->depth == 0;
    sync_stack_top(engine);
    if (is_outermost) {
        engine->deadline_ms = 0;
        engine->abort_flag = abort_flag;
    }

    int32_t ret;
    // 分组位置之外，执行器还要用寄存器，缓冲区按 alloc_count 分配（见 js_regexp_exec 的注释）
    int alloc_count = lre_get_alloc_count(bytecode);
    uint8_t **capture = alloc_count > 0 ? malloc(sizeof(capture[0]) * alloc_count) : NULL;
    if (alloc_count > 0 && capture == NULL) {
        ret = -2;
    } else if (is_outermost && is_aborted(engine)) {
        // 和 qjs_eval 一样先查一次：短输入在执行器第一次轮询之前就结束了
        ret = -1;
    } else {
        const uint8_t *buf = (const uint8_t *)input;
        int rc = lre_exec(capture, bytecode, buf, start, len, 1, engine->ctx);
        if (rc == 1) {
            int count = lre_get_capture_count(bytecode);
            for (int i = 0; i < count; i++) {
                uint8_t *from = capture[2 * i];
                uint8_t *to = capture[2 * i + 1];
                bool matched = from != NULL && to != NULL;
                captures[2 * i] = matched ? (int32_t)((from - buf) >> 1) : -1;
                captures[2 * i + 1] = matched ? (int32_t)((to - buf) >> 1) : -1;
            }
            ret = 1;
        } else if (rc == 0) {
            ret = 0;
        } else {
            ret = rc == LRE_RET_TIMEOUT ? -1 : -2;
        }
    }
    free(capture);

    if (is_outermost) engine->abort_flag = NULL;
    return ret;
}

void qjs_regexp_free(QjsEngine *engine, uint8_t *bytecode) {
    js_free_rt(engine->rt, bytecode);
}
