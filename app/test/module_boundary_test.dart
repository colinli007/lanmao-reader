import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 书源模块的边界（设计 D1）：rule_engine 只能在 lib/online/ 里引用，书架、阅读器、存储层不依赖引擎，
/// 以后建 store flavor 时只替换 online/。
void main() {
  test('lib/online/ 以外不引用 rule_engine', () {
    final offenders = [
      for (final file in Directory('lib').listSync(recursive: true).whereType<File>())
        if (file.path.endsWith('.dart') &&
            !file.path.startsWith('lib/online/') &&
            file.readAsStringSync().contains(RegExp(r'''^(import|export) +['"]package:rule_engine/''', multiLine: true)))
          file.path,
    ];
    expect(offenders, isEmpty, reason: '这些文件引用了 rule_engine');
  });
}
