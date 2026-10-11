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
}

void _writeFlagLater((int, int) args) {
  final (address, delayMs) = args;
  sleep(Duration(milliseconds: delayMs));
  Pointer<Int32>.fromAddress(address).value = 1;
}
