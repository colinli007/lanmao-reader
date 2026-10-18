// 隔离求值的开销：连续 2000 次，每次新建变量层、注入 5 个变量、求值一个短表达式。
//   ./tool/build_host.sh
//   QUICKJS_NG_FFI_LIB=$PWD/build/host/libquickjs_ng_ffi.dylib dart run tool/bench_scoped_eval.dart
// ignore_for_file: avoid_print
import 'package:quickjs_ng_ffi/quickjs_ng_ffi.dart';

void main() {
  final engine = JsEngine();
  final lib = JsLib(engine, 'function fmt(s) { return s.trim(); }');
  const count = 2000;

  double run({JsLib? lib, String code = 'result.trim()'}) {
    final watch = Stopwatch()..start();
    for (var i = 0; i < count; i++) {
      final layer = JsLayer(engine);
      engine.evalScoped(code, layer: layer, lib: lib, vars: {
        'result': '  第$i章 标题  ',
        'baseUrl': 'https://www.example.com/book/1/',
        'book': {'name': '三体', 'author': '刘慈欣', 'bookUrl': 'https://www.example.com/book/1'},
        'chapter': {'title': '第$i章', 'index': i},
        'title': '第$i章',
      });
      layer.dispose();
    }
    return watch.elapsedMicroseconds / 1000;
  }

  run(); // 预热
  final plain = run();
  final withLib = run(lib: lib, code: 'fmt(result)');
  final watch = Stopwatch()..start();
  for (var i = 0; i < count; i++) {
    engine.eval("'  第$i章 标题  '.trim()");
  }
  final baseline = watch.elapsedMicroseconds / 1000;
  print('隔离求值 $count 次：${plain.toStringAsFixed(1)} ms');
  print('隔离求值 + jsLib $count 次：${withLib.toStringAsFixed(1)} ms');
  print('对照：普通求值 $count 次：${baseline.toStringAsFixed(1)} ms');
  engine.dispose();
}
