// 在开发机上运行：
//   ./tool/build_host.sh
//   QUICKJS_NG_FFI_LIB=build/host/libquickjs_ng_ffi.dylib dart test
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:quickjs_ng_ffi/quickjs_ng_ffi.dart';
import 'package:test/test.dart';

void main() {
  late JsEngine engine;

  setUp(() => engine = JsEngine());
  tearDown(() => engine.dispose());

  test('求值并按 JSON 返回', () {
    expect(engine.eval('1 + 2'), 3);
    expect(engine.eval('({a: [1, "x", null], b: true})'), {
      'a': [1, 'x', null],
      'b': true,
    });
    expect(engine.eval('undefined'), isNull);
    expect(engine.eval('"中文"'), '中文');
  });

  test('JS 同步调用宿主函数并拿到返回值', () {
    engine.register('java.md5Encode', (args) => 'md5(${args[0]})');
    engine.register('java.put', (args) => args[1]);
    expect(engine.eval('java.md5Encode("abc") + "|" + java.put("k", 42)'), 'md5(abc)|42');
  });

  test('宿主函数里再次求值（规则引擎回调 JS 的嵌套场景）', () {
    // 模拟 java.getString(rule)：规则里又带 @js:，需要在同一个引擎里嵌套求值
    engine.register('java.getString', (args) {
      final rule = args[0] as String;
      return engine.eval(rule.substring('@js:'.length));
    });
    engine.setGlobal('result', 'hello');
    expect(
      engine.eval('java.getString("@js:result.toUpperCase() + java.getString(\'@js:1+1\')")'),
      'HELLO2',
    );
  });

  test('宿主函数抛出的异常变成 JS 异常，可以被 try/catch', () {
    engine.register('java.ajax', (args) => throw StateError('网络不可用'));
    expect(
      engine.eval('try { java.ajax("x") } catch (e) { "caught:" + e.message }'),
      contains('网络不可用'),
    );
    expect(() => engine.eval('java.ajax("x")'), throwsA(isA<JsException>()));
  });

  test('死循环按超时中断，引擎之后仍可用', () {
    final watch = Stopwatch()..start();
    expect(
      () => engine.eval('while (true) {}', timeout: const Duration(milliseconds: 200)),
      throwsA(isA<JsException>().having((e) => e.message, 'message', contains('interrupted'))),
    );
    expect(watch.elapsedMilliseconds, lessThan(2000));
    expect(engine.eval('40 + 2'), 42);
  });

  test('内存上限生效', () {
    final small = JsEngine(memoryLimitBytes: 8 * 1024 * 1024);
    addTearDown(small.dispose);
    expect(
      () => small.eval('let a = []; while (true) a.push("x".repeat(1024));'),
      throwsA(isA<JsException>()),
    );
  });

  test('语法错误带消息', () {
    expect(
      () => engine.eval('function ('),
      throwsA(isA<JsException>().having((e) => e.message, 'message', contains('SyntaxError'))),
    );
  });

  test('大量宿主调用不崩溃', () {
    var count = 0;
    engine.register('java.log', (args) => ++count);
    expect(engine.eval('let s = 0; for (let i = 0; i < 20000; i++) s += java.log(i); s'), isA<num>());
    expect(count, 20000);
  });

  group('外部中止信号', () {
    late Pointer<Int32> abort;

    setUp(() => abort = calloc<Int32>());
    tearDown(() => calloc.free(abort));

    // eval 是同步 FFI 调用，求值期间本 isolate 的事件循环不转，所以由另一个 isolate 延时写标志
    Future<void> abortAfter(Duration delay) =>
        Isolate.spawn(_writeFlagLater, (abort.address, delay.inMilliseconds));

    Matcher interrupted() =>
        throwsA(isA<JsException>().having((e) => e.message, 'message', contains('interrupted')));

    test('中止死循环，引擎之后仍可用', () async {
      await abortAfter(const Duration(milliseconds: 200));
      final watch = Stopwatch()..start();
      expect(() => engine.eval('while (true) {}', abortSignal: abort), interrupted());
      expect(watch.elapsedMilliseconds, lessThan(2000));
      expect(engine.eval('"still alive"'), 'still alive');
    });

    test('try/catch 捕获不到中止', () async {
      await abortAfter(const Duration(milliseconds: 200));
      expect(
        () => engine.eval('while (true) { try { while (true) {} } catch (e) {} }', abortSignal: abort),
        interrupted(),
      );
    });

    test('求值开始前信号已设置时不执行任何代码', () {
      var calls = 0;
      engine.register('host.mark', (args) => ++calls);
      abort.value = 1;
      expect(() => engine.eval('host.mark()', abortSignal: abort), interrupted());
      expect(calls, 0);
    });

    test('外层 JS 捕获不到嵌套求值的中止', () async {
      engine.register('host.nested', (args) => engine.eval(args[0] as String));
      await abortAfter(const Duration(milliseconds: 200));
      expect(
        () => engine.eval('try { host.nested("while (true) {}") } catch (e) {} "continued"', abortSignal: abort),
        interrupted(),
      );
    });

    test('宿主函数吞掉中止后正常返回，调用方 JS 仍被中止', () async {
      engine.register('host.nested', (args) {
        try {
          return engine.eval(args[0] as String);
        } on JsException {
          return '';
        }
      });
      await abortAfter(const Duration(milliseconds: 200));
      expect(
        () => engine.eval('host.nested("while (true) {}") + "continued"', abortSignal: abort),
        interrupted(),
      );
    });

    test('信号在宿主函数执行期间被设置，宿主函数报普通错误也拦不住中止', () async {
      engine.register('host.wait', (args) {
        sleep(const Duration(milliseconds: 400));
        throw StateError('普通错误');
      });
      await abortAfter(const Duration(milliseconds: 200));
      expect(
        () => engine.eval('try { host.wait() } catch (e) {} "continued"', abortSignal: abort),
        interrupted(),
      );
    });
  });

  group('可中断的正则', _regExpTests);
  group('隔离求值', _scopedTests);
}

void _scopedTests() {
  late JsEngine engine;

  setUp(() => engine = JsEngine());
  tearDown(() => engine.dispose());

  Object? evalOnce(String code, {Map<String, Object?>? vars, JsLib? lib}) {
    final layer = JsLayer(engine);
    try {
      return engine.evalScoped(code, layer: layer, lib: lib, vars: vars);
    } finally {
      layer.dispose();
    }
  }

  test('声明不泄漏', () {
    expect(evalOnce('var a = 1; function f() {} b = 2; let c = 3; a'), 1);
    expect(evalOnce('[typeof a, typeof f, typeof b, typeof c].join()'), 'undefined,undefined,undefined,undefined');
    expect(engine.eval('typeof b'), 'undefined');
  });

  test('变量层上的变量，顶层 this 是变量层', () {
    expect(evalOnce('this.result + result.length', vars: {'result': 'abc'}), 'abc3');
  });

  test('宿主全局：全局、变量层的 this、jsLib 的顶层和函数里都能用，jsLib 新增的名字不含它们', () {
    engine.eval('__qjs.setGlobals({ hostThing: { name: "h" } })');
    expect(evalOnce('hostThing.name + this.hostThing.name'), 'hh');
    final lib = JsLib(engine, 'var atInit = hostThing.name; function later() { return hostThing.name + this.hostThing.name; }');
    addTearDown(lib.dispose);
    expect(evalOnce('atInit + later() + Object.keys(this).length', lib: lib), 'hhh0');
    // 变量层上赋值只遮蔽本次求值
    expect(evalOnce('hostThing = 1; hostThing'), 1);
    expect(evalOnce('hostThing.name'), 'h');
  });

  test('复用变量层', () {
    final layer = JsLayer(engine);
    addTearDown(layer.dispose);
    expect(engine.evalScoped('g++; k = 1; g', layer: layer, vars: {'g': 0}), 1);
    expect(engine.evalScoped('g++; [g, k].join()', layer: layer), '2,1');
  });

  test('非严格模式，看不到包装函数的形参和局部变量', () {
    expect(evalOnce('for (i in [1, 2]) {}; i'), '1');
    expect(evalOnce('[typeof layer, typeof code, typeof run, typeof layers].join()'),
        'undefined,undefined,undefined,undefined');
  });

  test('嵌套求值里外层未声明的赋值不被内层搬走', () {
    engine.register('host.nested', (args) => evalOnce(args[0] as String));
    expect(evalOnce('x = 1; var inner = host.nested("y = 2; typeof x"); [inner, x, typeof y].join()'),
        'number,1,undefined');
  });

  test('宿主函数抛出不可捕获的错误，外层 try/catch 拦不住', () {
    engine.register('host.deep', (args) => throw JsException('嵌套太深', uncatchable: true));
    engine.register('host.nested', (args) => evalOnce(args[0] as String));
    expect(
      () => evalOnce('try { host.nested("try { host.deep() } catch (e) {} 1") } catch (e) {} "continued"'),
      throwsA(isA<JsException>()
          .having((e) => e.message, 'message', contains('嵌套太深'))
          .having((e) => e.uncatchable, 'uncatchable', isTrue)),
    );
    expect(evalOnce('1 + 1'), 2);
  });

  test('以超时或不可捕获的错误结束时，未声明的赋值也移到变量层', () {
    engine.register('host.deep', (args) => throw JsException('嵌套太深', uncatchable: true));
    engine.register('host.nested', (args) => evalOnce(args[0] as String));
    final layer = JsLayer(engine);
    addTearDown(layer.dispose);
    expect(() => engine.evalScoped('a = 1; while (true) {}', layer: layer, timeout: const Duration(milliseconds: 50)),
        throwsA(isA<JsException>().having((e) => e.uncatchable, 'uncatchable', isTrue)));
    expect(() => evalOnce('b = 1; host.nested("c = 1; host.deep()")'),
        throwsA(isA<JsException>().having((e) => e.uncatchable, 'uncatchable', isTrue)));
    expect(engine.eval('[typeof a, typeof b, typeof c].join()'), 'undefined,undefined,undefined');
    expect(engine.evalScoped('a', layer: layer), 1);
  });

  test('__qjs.replacer 和 revive 钩子', () {
    engine.eval('''__qjs.replacer = function (k, v) { return typeof v === 'number' && !isFinite(v) ? {n: String(v)} : v; };
      __qjs.revive = function (vars) { vars.x = vars.x * 2; return vars; };''');
    engine.register('host.echo', (args) => args);
    expect(evalOnce('0 / 0'), {'n': 'NaN'});
    expect(evalOnce('host.echo(1 / 0, 2)'), [{'n': 'Infinity'}, 2]);
    expect(evalOnce('x + 1', vars: {'x': 20}), 41);
  });

  test('普通错误可以被 try/catch，不是不可捕获的', () {
    expect(evalOnce('try { null.x } catch (e) { "caught" }'), 'caught');
    expect(() => evalOnce('null.x'),
        throwsA(isA<JsException>().having((e) => e.uncatchable, 'uncatchable', isFalse)));
  });

  group('jsLib', () {
    test('共享作用域只读遮蔽', () {
      final lib = JsLib(engine, 'var n = 5; function get() { return n; }');
      addTearDown(lib.dispose);
      expect(evalOnce('n = 9; get()', lib: lib), 5);
      expect(evalOnce('n', lib: lib), 5);
    });

    test('jsLib 的函数改自己的顶层变量，后续求值可见', () {
      final lib = JsLib(engine, 'var n = 0; function inc() { return ++n; }');
      addTearDown(lib.dispose);
      expect(evalOnce('inc()', lib: lib), 1);
      expect(evalOnce('inc()', lib: lib), 2);
    });

    test('jsLib 函数以 f() 调用时 this 是变量层', () {
      final lib = JsLib(engine, "function r() { return this.result + '!'; }");
      addTearDown(lib.dispose);
      expect(evalOnce('r()', lib: lib, vars: {'result': 'a'}), 'a!');
    });

    test('没有 jsLib 时看不到它的名字', () {
      final lib = JsLib(engine, 'var only = 1;');
      addTearDown(lib.dispose);
      expect(evalOnce('typeof only'), 'undefined');
      expect(evalOnce('typeof only', lib: lib), 'number');
    });

    test('jsLib 出错时带回原因', () {
      expect(() => JsLib(engine, 'throw new Error("坏了")'),
          throwsA(isA<JsException>().having((e) => e.message, 'message', contains('坏了'))));
      expect(() => JsLib(engine, 'function ('),
          throwsA(isA<JsException>().having((e) => e.message, 'message', contains('SyntaxError'))));
    });

    test('jsLib 里的死循环能被中止标志打断', () async {
      final abort = calloc<Int32>();
      addTearDown(() => calloc.free(abort));
      final lib = JsLib(engine, 'function spin() { while (true) {} }');
      addTearDown(lib.dispose);
      await Isolate.spawn(_writeFlagLater, (abort.address, 200));
      final layer = JsLayer(engine);
      addTearDown(layer.dispose);
      expect(
        () => engine.evalScoped('try { spin() } catch (e) {} "continued"', layer: layer, lib: lib, abortSignal: abort),
        throwsA(isA<JsException>().having((e) => e.message, 'message', contains('interrupted'))),
      );
      abort.value = 0;
      expect(() => JsLib(engine, 'while (true) {}', timeout: const Duration(milliseconds: 100)),
          throwsA(isA<JsException>().having((e) => e.message, 'message', contains('interrupted'))));
    });

    test('释放后再用以错误结束', () {
      final lib = JsLib(engine, 'var n = 1;');
      lib.dispose();
      expect(() => evalOnce('n', lib: lib), throwsStateError);
    });

    test('引擎释放时一并释放', () {
      final other = JsEngine();
      final lib = JsLib(other, 'function f() { return 1; }');
      final layer = JsLayer(other);
      expect(other.evalScoped('f()', layer: layer, lib: lib), 1);
      other.dispose();
      lib.dispose();
      layer.dispose();
    });
  });
}

void _regExpTests() {
  late JsEngine engine;
  late Pointer<Int32> abort;

  setUp(() {
    engine = JsEngine();
    abort = calloc<Int32>();
  });
  tearDown(() {
    engine.dispose();
    calloc.free(abort);
  });

  test('分组匹配，未参与匹配的组为空', () {
    final match = JsRegExp(engine, r'(\d+)-(\d+)?').firstMatch('a 12- b')!;
    expect(match.input.substring(match.start, match.end), '12-');
    expect(match.group(1), '12');
    expect(match.group(2), isNull);
    expect(match.groupStart(2), -1);
  });

  test('中止灾难性回溯，之后同一个正则仍可用', () async {
    final regExp = JsRegExp(engine, r'(a+)+b');
    await Isolate.spawn(_writeFlagLater, (abort.address, 200));
    final watch = Stopwatch()..start();
    expect(
      () => regExp.firstMatch('a' * 30, abortSignal: abort),
      throwsA(isA<JsException>().having((e) => e.message, 'message', contains('interrupted'))),
    );
    expect(watch.elapsedMilliseconds, lessThan(2000));
    abort.value = 0;
    final match = regExp.firstMatch('aab', abortSignal: abort)!;
    expect(match.group(0), 'aab');
    expect(engine.eval('1 + 1'), 2);
  });

  test('编译失败带有原因', () {
    expect(
      () => JsRegExp(engine, '[未闭合'),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('unexpected end'))),
    );
  });

  test('Unicode 标志下代理对算一个字符', () {
    final match = JsRegExp(engine, '第(.)章', unicode: true).firstMatch('第𠀀章')!;
    expect(match.group(1), '𠀀');
  });

  test('非 Unicode 模式下 pattern 里的 BMP 以外字符按两个代理项匹配', () {
    expect(JsRegExp(engine, r'\s*🍵\s*').firstMatch('a 🍵 b')?.start, 1);
    expect(JsRegExp(engine, '📖').allMatches('📖x📖'), hasLength(2));
  });

  test('标志与 (?i:) 修饰符', () {
    expect(JsRegExp(engine, 'abc', ignoreCase: true).firstMatch('xABC')?.start, 1);
    expect(JsRegExp(engine, '(?i:a)b').firstMatch('Ab ab AB')?.start, 0);
    expect(JsRegExp(engine, '^b', multiLine: true).firstMatch('a\nb')?.start, 2);
    expect(JsRegExp(engine, 'a.b', dotAll: true).firstMatch('a\nb')?.start, 0);
    expect(JsRegExp(engine, 'a.b').firstMatch('a\nb'), isNull);
  });

  test('allMatches 跳过空匹配，命名分组', () {
    final regExp = JsRegExp(engine, r'(?<n>\d*)');
    final matches = regExp.allMatches('1a22');
    expect(matches.map((m) => m.group(0)).toList(), ['1', '', '22', '']);
    expect(matches.first.namedGroup('n'), '1');
    expect(regExp.groupIndex('n'), 1);
    expect(JsRegExp(engine, 'x').allMatches(''), isEmpty);
  });

  test('嵌套在求值里时沿用外层的中止标志', () async {
    final regExp = JsRegExp(engine, r'(a+)+b');
    engine.register('host.match', (args) => regExp.firstMatch(args[0] as String)?.start);
    await Isolate.spawn(_writeFlagLater, (abort.address, 200));
    expect(
      () => engine.eval('try { host.match("${'a' * 30}") } catch (e) {} "continued"', abortSignal: abort),
      throwsA(isA<JsException>().having((e) => e.message, 'message', contains('interrupted'))),
    );
  });

  test('引擎释放时一并释放正则', () {
    final other = JsEngine();
    final regExp = JsRegExp(other, 'a');
    other.dispose();
    expect(() => regExp.firstMatch('a'), throwsStateError);
  });
}

void _writeFlagLater((int, int) args) {
  final (address, delayMs) = args;
  sleep(Duration(milliseconds: delayMs));
  Pointer<Int32>.fromAddress(address).value = 1;
}
