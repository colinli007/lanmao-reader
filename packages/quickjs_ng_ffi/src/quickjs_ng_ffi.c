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
    // 预置 JS 里的 __qjs 对象：变量层、jsLib 和隔离求值的实现
    JSValue state;
    // jsLib 的 realm，下标是编号减 1，释放后置 NULL
    JSContext **libs;
    int32_t lib_count;
    int32_t lib_capacity;
};

// 隔离求值和 jsLib 的 JS 部分，引擎创建时执行一次。
//
// run 用 Function 构造，所以它的作用域链上只有全局，书源代码看不到这里的局部变量；
// 它不声明形参，代码和变量层都从 arguments 取。直接 eval 让 var 和函数声明落在 run 这次调用里，
// let/const 落在 eval 自己的词法环境里；with 让代码按名字读写变量层，顶层 this 是变量层。
// 未声明的赋值会落到全局对象上：enterScope 记下求值前的全局属性名，leaveScope 把新增的移到变量层上。
// leaveScope 由 C 在求值后单独调用，而不是写在 finally 里：中止、超时和宿主要求的不可捕获错误展开时不进 finally。
//
// jsLib 的 Proxy：has / get 只认 jsLib 新增的全局名（和 Object.prototype 上的名字，与没有 jsLib 时一致），
// set 把值定义到接收者（变量层）上，所以给 jsLib 的名字赋值只遮蔽、不修改。
//
// 宿主全局（setGlobals，如规则引擎的 Java 包对象）：定义在全局对象上，也放在 hostProto 上。变量层和 jsLib 的 Proxy
// 都以 hostProto 为底，所以变量层的 this 上也能读到（Rhino 里作用域对象的原型链通到顶层作用域）；
// jsLib 的 realm 执行之前，initLib 把它们复制到 jsLib 的全局对象上，jsLib 的代码也能直接用。
static const char PRELUDE[] =
    "(function () {\n"
    "  'use strict';\n"
    "  var G = globalThis, ownKeys = Reflect.ownKeys, objectProto = Object.prototype;\n"
    "  var hostProto = Object.create(objectProto);\n"
    "  var run = Function('with (arguments[0]) return eval(arguments[1]);');\n"
    "  var layers = new Map(), libs = new Map(), nextLayer = 1;\n"
    "  function own(value) { return { value: value, writable: true, enumerable: true, configurable: true }; }\n"
    "  var state = { revive: null, replacer: null };\n"
    "  state.setGlobals = function (globals) {\n"
    "    var names = Object.keys(globals);\n"
    "    for (var i = 0; i < names.length; i++) {\n"
    "      var desc = { value: globals[names[i]], writable: true, configurable: true };\n"
    "      Reflect.defineProperty(G, names[i], desc);\n"
    "      Reflect.defineProperty(hostProto, names[i], desc);\n"
    "    }\n"
    "  };\n"
    "  state.initLib = function (lib) {\n"
    "    var names = ownKeys(hostProto);\n"
    "    for (var i = 0; i < names.length; i++)\n"
    "      Reflect.defineProperty(lib, names[i], Reflect.getOwnPropertyDescriptor(hostProto, names[i]));\n"
    "  };\n"
    "  state.newLayer = function () { var id = nextLayer++; layers.set(id, {}); return id; };\n"
    "  state.freeLayer = function (id) { layers.delete(id); };\n"
    "  state.addLib = function (id, lib, before, after) {\n"
    "    var known = new Set(before), names = new Set();\n"
    "    for (var i = 0; i < after.length; i++) if (!known.has(after[i])) names.add(after[i]);\n"
    "    libs.set(id, new Proxy({}, {\n"
    "      has: function (target, key) { return names.has(key) || key in hostProto; },\n"
    "      get: function (target, key, receiver) {\n"
    "        return names.has(key) ? lib[key] : Reflect.get(hostProto, key, receiver);\n"
    "      },\n"
    "      set: function (target, key, value, receiver) { return Reflect.defineProperty(receiver, key, own(value)); }\n"
    "    }));\n"
    "  };\n"
    "  state.freeLib = function (id) { libs.delete(id); };\n"
    "  state.enterScope = function (layerId, libId, vars) {\n"
    "    var layer = layers.get(layerId);\n"
    "    if (layer === undefined) throw new Error('变量层不存在：' + layerId);\n"
    "    var proto = hostProto;\n"
    "    if (libId !== 0) {\n"
    "      proto = libs.get(libId);\n"
    "      if (proto === undefined) throw new Error('jsLib 不存在：' + libId);\n"
    "    }\n"
    "    if (Reflect.getPrototypeOf(layer) !== proto) Reflect.setPrototypeOf(layer, proto);\n"
    "    if (vars != null) {\n"
    "      if (typeof state.revive === 'function') vars = state.revive(vars);\n"
    "      var names = Object.keys(vars);\n"
    "      for (var i = 0; i < names.length; i++) Reflect.defineProperty(layer, names[i], own(vars[names[i]]));\n"
    "    }\n"
    "    return { layer: layer, before: new Set(ownKeys(G)) };\n"
    "  };\n"
    "  state.evalInScope = function (scope, code) { return run.call(scope.layer, scope.layer, code); };\n"
    "  state.leaveScope = function (scope) {\n"
    "    var after = ownKeys(G);\n"
    "    for (var j = 0; j < after.length; j++) {\n"
    "      var key = after[j];\n"
    "      if (scope.before.has(key)) continue;\n"
    "      var desc = Reflect.getOwnPropertyDescriptor(G, key);\n"
    "      if (Reflect.deleteProperty(G, key)) Reflect.defineProperty(scope.layer, key, desc);\n"
    "    }\n"
    "  };\n"
    "  Object.defineProperty(G, '__qjs', { value: state });\n"
    "  return state;\n"
    "})()";

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
// is_error 不为 NULL 时写入 1，不可捕获的异常（中止、宿主函数要求的）写入 2。
static char *take_exception(JSContext *ctx, int32_t *is_error) {
    JSValue exception = JS_GetException(ctx);
    if (is_error != NULL) *is_error = JS_IsUncatchableError(exception) ? 2 : 1;
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
// __qjs.replacer 是函数时作为 JSON.stringify 的 replacer（预置 JS 用它表示 NaN 这类 JSON 没有的值）。
static char *to_json(JSContext *ctx, JSValueConst value, int32_t *is_error) {
    if (JS_IsUndefined(value)) return NULL;
    QjsEngine *engine = JS_GetContextOpaque(ctx);
    JSValue replacer = JS_GetPropertyStr(ctx, engine->state, "replacer");
    JSValue json = JS_JSONStringify(ctx, value, JS_IsFunction(ctx, replacer) ? replacer : JS_UNDEFINED, JS_UNDEFINED);
    JS_FreeValue(ctx, replacer);
    if (JS_IsException(json)) return take_exception(ctx, is_error);
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
        if (is_error == 2) {
            // 取出刚抛出的错误对象，标记为不可捕获后重新抛出
            JSValue exception = JS_GetException(ctx);
            JS_SetUncatchableError(ctx, exception);
            return JS_Throw(ctx, exception);
        }
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
    JS_SetContextOpaque(engine->ctx, engine);
    JS_SetInterruptHandler(engine->rt, interrupt_handler, engine);
    engine->state = JS_Eval(engine->ctx, PRELUDE, strlen(PRELUDE), "<prelude>", JS_EVAL_TYPE_GLOBAL);
    if (JS_IsException(engine->state)) {
        JS_FreeContext(engine->ctx);
        JS_FreeRuntime(engine->rt);
        free(engine);
        return NULL;
    }
    // 预置 JS 执行完再设内存上限，上限很小时也不会在这里失败
    if (memory_limit_bytes > 0) JS_SetMemoryLimit(engine->rt, (size_t)memory_limit_bytes);
    return engine;
}

void qjs_free(QjsEngine *engine) {
    if (engine == NULL) return;
    for (int32_t i = 0; i < engine->lib_count; i++) {
        if (engine->libs[i] != NULL) JS_FreeContext(engine->libs[i]);
    }
    free(engine->libs);
    JS_FreeValue(engine->ctx, engine->state);
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
    if (JS_IsException(value)) return take_exception(ctx, NULL);
    JSValue global = JS_GetGlobalObject(ctx);
    int status = JS_SetPropertyStr(ctx, global, name, value);
    JS_FreeValue(ctx, global);
    return status < 0 ? take_exception(ctx, NULL) : NULL;
}

// 从 Dart 进入求值：最外层设置截止时间和中止标志，嵌套调用沿用外层的。返回是否最外层。
static bool enter_eval(QjsEngine *engine, int32_t timeout_ms, const int32_t *abort_flag) {
    bool is_outermost = engine->depth == 0;
    sync_stack_top(engine);
    if (is_outermost) {
        engine->deadline_ms = timeout_ms > 0 ? now_ms() + timeout_ms : 0;
        engine->abort_flag = abort_flag;
    }
    engine->depth++;
    return is_outermost;
}

static void leave_eval(QjsEngine *engine, bool is_outermost) {
    engine->depth--;
    if (is_outermost) {
        engine->deadline_ms = 0;
        engine->abort_flag = NULL;
    }
}

// 中断回调只在循环回边和函数调用处轮询，没有循环的代码可能一次都不检查，所以最外层先查一次
static bool aborted_before_start(QjsEngine *engine, bool is_outermost) {
    return is_outermost && is_aborted(engine);
}

// 把求值结果（或异常）转成返回给 Dart 的字符串，并释放 value
static char *finish_eval(JSContext *ctx, JSValue value, int32_t *is_error) {
    char *out = JS_IsException(value) ? take_exception(ctx, is_error) : to_json(ctx, value, is_error);
    JS_FreeValue(ctx, value);
    return out;
}

char *qjs_eval(QjsEngine *engine, const char *code, const char *filename, int32_t timeout_ms,
               const int32_t *abort_flag, int32_t *is_error) {
    JSContext *ctx = engine->ctx;
    *is_error = 0;
    bool is_outermost = enter_eval(engine, timeout_ms, abort_flag);
    JSValue value = aborted_before_start(engine, is_outermost)
                        ? throw_interrupted(ctx)
                        : JS_Eval(ctx, code, strlen(code), filename, JS_EVAL_TYPE_GLOBAL);
    char *out = finish_eval(ctx, value, is_error);
    leave_eval(engine, is_outermost);
    return out;
}

// 调用 __qjs 上的方法，argv 由调用方持有
static JSValue call_state(QjsEngine *engine, const char *method, int argc, JSValueConst *argv) {
    JSValue fn = JS_GetPropertyStr(engine->ctx, engine->state, method);
    JSValue result = JS_Call(engine->ctx, fn, engine->state, argc, argv);
    JS_FreeValue(engine->ctx, fn);
    return result;
}

int32_t qjs_layer_new(QjsEngine *engine) {
    sync_stack_top(engine);
    JSValue id = call_state(engine, "newLayer", 0, NULL);
    int32_t out = 0;
    if (JS_IsException(id)) {
        free(take_exception(engine->ctx, NULL));
    } else {
        JS_ToInt32(engine->ctx, &out, id);
    }
    JS_FreeValue(engine->ctx, id);
    return out;
}

void qjs_layer_free(QjsEngine *engine, int32_t layer_id) {
    sync_stack_top(engine);
    JSValue arg = JS_NewInt32(engine->ctx, layer_id);
    JS_FreeValue(engine->ctx, call_state(engine, "freeLayer", 1, &arg));
}

// 把求值期间新增的全局属性移到变量层，求值以异常结束时也要做。
// 中止或超时后中断回调会立刻打断任何 JS，所以先取出未处理的异常、暂停截止时间和中止标志，移完恢复并重新抛出
static void leave_scope(QjsEngine *engine, JSValueConst scope) {
    JSContext *ctx = engine->ctx;
    JSValue exception = JS_GetException(ctx);
    int64_t deadline_ms = engine->deadline_ms;
    const int32_t *abort_flag = engine->abort_flag;
    engine->deadline_ms = 0;
    engine->abort_flag = NULL;
    JSValue result = call_state(engine, "leaveScope", 1, &scope);
    // 移动本身失败（如内存不足）时丢掉它的异常，保留求值的结果或异常
    if (JS_IsException(result)) JS_FreeValue(ctx, JS_GetException(ctx));
    JS_FreeValue(ctx, result);
    engine->deadline_ms = deadline_ms;
    engine->abort_flag = abort_flag;
    if (!JS_IsUninitialized(exception)) JS_Throw(ctx, exception);
}

char *qjs_eval_scoped(QjsEngine *engine, int32_t layer_id, int32_t lib_id, const char *vars_json, const char *code,
                      int32_t timeout_ms, const int32_t *abort_flag, int32_t *is_error) {
    JSContext *ctx = engine->ctx;
    *is_error = 0;
    bool is_outermost = enter_eval(engine, timeout_ms, abort_flag);
    JSValue value;
    if (aborted_before_start(engine, is_outermost)) {
        value = throw_interrupted(ctx);
    } else {
        JSValue vars = vars_json != NULL ? JS_ParseJSON(ctx, vars_json, strlen(vars_json), "<vars>") : JS_NULL;
        JSValue scope = JS_EXCEPTION;
        if (!JS_IsException(vars)) {
            JSValue argv[3] = {JS_NewInt32(ctx, layer_id), JS_NewInt32(ctx, lib_id), vars};
            scope = call_state(engine, "enterScope", 3, argv);
            JS_FreeValue(ctx, vars);
        }
        if (JS_IsException(scope)) {
            value = JS_EXCEPTION;
        } else {
            JSValue argv[2] = {scope, JS_NewString(ctx, code)};
            value = call_state(engine, "evalInScope", 2, argv);
            JS_FreeValue(ctx, argv[1]);
            leave_scope(engine, scope);
            JS_FreeValue(ctx, scope);
        }
    }
    char *out = finish_eval(ctx, value, is_error);
    leave_eval(engine, is_outermost);
    return out;
}

// 在 jsLib 的 realm 里取全局对象的自有属性名
static JSValue global_names(JSContext *ctx) {
    static const char code[] = "Object.getOwnPropertyNames(globalThis)";
    return JS_Eval(ctx, code, sizeof(code) - 1, "<lib>", JS_EVAL_TYPE_GLOBAL);
}

static int32_t add_lib_slot(QjsEngine *engine, JSContext *lib) {
    if (engine->lib_count == engine->lib_capacity) {
        int32_t capacity = engine->lib_capacity == 0 ? 8 : engine->lib_capacity * 2;
        JSContext **libs = realloc(engine->libs, sizeof(JSContext *) * (size_t)capacity);
        if (libs == NULL) return 0;
        engine->libs = libs;
        engine->lib_capacity = capacity;
    }
    engine->libs[engine->lib_count++] = lib;
    return engine->lib_count;
}

int32_t qjs_lib_new(QjsEngine *engine, const char *code, const char *filename, int32_t timeout_ms,
                    const int32_t *abort_flag, char **error, int32_t *is_error) {
    *error = NULL;
    *is_error = 0;
    bool is_outermost = enter_eval(engine, timeout_ms, abort_flag);
    int32_t lib_id = 0;

    JSContext *lib = JS_NewContext(engine->rt);
    if (lib == NULL) {
        *is_error = 1;
        *error = dup_literal("创建 jsLib 的 JSContext 失败");
    } else if (aborted_before_start(engine, is_outermost)) {
        JS_FreeValue(lib, throw_interrupted(lib));
        *error = take_exception(lib, is_error);
        JS_FreeContext(lib);
    } else {
        JS_SetContextOpaque(lib, engine);
        JSValue global = JS_GetGlobalObject(lib);
        JSValue inited = call_state(engine, "initLib", 1, &global);
        JSValue before = JS_IsException(inited) ? JS_EXCEPTION : global_names(lib);
        JS_FreeValue(engine->ctx, inited);
        JSValue result = JS_IsException(before) ? JS_EXCEPTION : JS_Eval(lib, code, strlen(code), filename,
                                                                           JS_EVAL_TYPE_GLOBAL);
        JSValue after = JS_IsException(result) ? JS_EXCEPTION : global_names(lib);
        if (JS_IsException(after) || JS_PreventExtensions(lib, global) < 0) {
            // 同一个运行时里的异常只有一份，用哪个 JSContext 取都一样
            *error = take_exception(lib, is_error);
        } else {
            lib_id = add_lib_slot(engine, lib);
            JSValue argv[4] = {JS_NewInt32(engine->ctx, lib_id), global, before, after};
            JSValue added = lib_id == 0 ? JS_ThrowOutOfMemory(engine->ctx) : call_state(engine, "addLib", 4, argv);
            if (JS_IsException(added)) {
                *error = take_exception(engine->ctx, is_error);
                if (lib_id != 0) engine->libs[lib_id - 1] = NULL;
                lib_id = 0;
            }
            JS_FreeValue(engine->ctx, added);
        }
        JS_FreeValue(lib, result);
        JS_FreeValue(lib, before);
        JS_FreeValue(lib, after);
        JS_FreeValue(lib, global);
        if (lib_id == 0) JS_FreeContext(lib);
    }
    leave_eval(engine, is_outermost);
    return lib_id;
}

void qjs_lib_free(QjsEngine *engine, int32_t lib_id) {
    if (lib_id <= 0 || lib_id > engine->lib_count || engine->libs[lib_id - 1] == NULL) return;
    sync_stack_top(engine);
    JSValue arg = JS_NewInt32(engine->ctx, lib_id);
    JS_FreeValue(engine->ctx, call_state(engine, "freeLib", 1, &arg));
    JS_FreeContext(engine->libs[lib_id - 1]);
    engine->libs[lib_id - 1] = NULL;
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
