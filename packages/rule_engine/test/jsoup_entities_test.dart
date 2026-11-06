import 'dart:convert';
import 'dart:io';

import 'package:rule_engine/src/html/jsoup_entities.dart';
import 'package:test/test.dart';

void main() {
  final fixture =
      jsonDecode(
            File('test/fixtures/jsoup_entities_cases.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  final cases = fixture['cases'] as List;
  for (var i = 0; i < cases.length; i++) {
    final item = cases[i] as Map<String, dynamic>;
    test('jsoup 1.16.2 oracle $i，inAttribute=${item['inAttribute']}', () {
      expect(
        unescapeJsoupEntities(
          item['input'] as String,
          item['inAttribute'] as bool,
        ),
        item['expected'],
      );
    });
  }
}
