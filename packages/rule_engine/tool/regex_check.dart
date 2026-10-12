// 统计书源正则的编译情况：把书源里的 `##` 净化正则、AllInOne 正则（`:` 开头的列表规则）、`bookUrlPattern`
// 按 Java 语法转换后用 libregexp 编译，列出编译失败的正则（这些在引擎里会退化为字面量替换）。
//
//   export QUICKJS_NG_FFI_LIB=$PWD/../quickjs_ng_ffi/build/host/libquickjs_ng_ffi.dylib
//   dart run tool/regex_check.dart --sources 书源.json [--only a.json]
import 'dart:convert';
import 'dart:io';

import 'package:rule_engine/rule_engine.dart';
import 'package:rule_engine/src/regex/source_regex.dart';

void main(List<String> args) {
  final options = {for (var i = 0; i + 1 < args.length; i += 2) args[i].substring(2): args[i + 1]};
  var sources = loadBookSources(File(options['sources']!).readAsStringSync()).sources;
  if (options['only'] case final only?) {
    final listed = jsonDecode(File(only).readAsStringSync()) as Map<String, Object?>;
    final urls = {for (final s in (listed['sources'] as List).cast<Map<String, Object?>>()) s['url']};
    sources = sources.where((s) => urls.contains(s.bookSourceUrl)).toList();
  }
  final seen = <String>{};
  sources = sources.where((s) => seen.add(s.bookSourceUrl)).toList();

  final patterns = <String>{};
  for (final source in sources) {
    if (source.bookUrlPattern case final pattern? when pattern.isNotEmpty) patterns.add(pattern);
    for (final group in [source.ruleSearch, source.ruleBookInfo, source.ruleToc, source.ruleContent]) {
      for (final key in _ruleKeys) {
        final rule = group[key];
        if (rule == null) continue;
        if (key == 'bookList' || key == 'chapterList') {
          final list = rule.replaceFirst(RegExp(r'^[-+]'), '');
          if (list.startsWith(':')) patterns.addAll(list.substring(1).split('&&').where((p) => p.trim().isNotEmpty));
        }
        for (final line in rule.split('\n')) {
          final parts = line.split('##');
          if (parts.length > 1 && parts[1].isNotEmpty) patterns.add(parts[1]);
        }
      }
    }
  }
  final failed = [for (final pattern in patterns) if (SourceRegex.tryCompile(pattern) == null) pattern];
  stdout.writeln('书源 ${sources.length} 个，不重复的正则 ${patterns.length} 个，编译失败 ${failed.length} 个');
  for (final pattern in failed) {
    stdout.writeln('  $pattern');
  }
  exit(0);
}

const List<String> _ruleKeys = [
  'bookList', 'name', 'author', 'kind', 'wordCount', 'lastChapter', 'intro', 'coverUrl', 'bookUrl', 'tocUrl', //
  'init', 'chapterList', 'chapterName', 'chapterUrl', 'isVolume', 'isVip', 'isPay', 'updateTime', 'nextTocUrl',
  'content', 'title', 'nextContentUrl', 'replaceRegex', 'downloadUrls',
];
