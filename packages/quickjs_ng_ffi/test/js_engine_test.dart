// 在开发机上运行：
//   ./tool/build_host.sh
//   QUICKJS_NG_FFI_LIB=build/host/libquickjs_ng_ffi.dylib dart test
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
}
