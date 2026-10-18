import 'dart:convert';

import '../text/lenient_json.dart';

/// 书源类型，取值和 Legado 一致。
enum BookSourceType {
  text,
  audio,
  image,
  file,
  video;

  static BookSourceType fromValue(int value) => value >= 0 && value < values.length ? values[value] : text;
}

/// 一组规则，如 `ruleSearch`。值都是字符串：JSON 里的数字、布尔按文本处理，对象和数组按紧凑 JSON 处理，
/// 和 MD3 的 `StringJsonDeserializer` 一致。
final class RuleGroup {
  const RuleGroup(this.name, this._rules);

  /// 规则组的名字，如 `ruleSearch`，用于错误信息里的字段位置。
  final String name;
  final Map<String, String> _rules;

  /// 规则，没有这个字段或值为 null 时返回 null。
  String? operator [](String key) => _rules[key];

  /// 错误信息里的字段位置，如 `ruleToc.chapterName`。
  String field(String key) => '$name.$key';
}

/// Legado 书源。只读：[json] 是导入时的原始对象，导出时原样输出。
final class BookSource {
  BookSource._(this.json)
    : bookSourceUrl = _string(json['bookSourceUrl'])!,
      bookSourceName = _string(json['bookSourceName']) ?? '',
      bookSourceType = BookSourceType.fromValue(_int(json['bookSourceType'])),
      header = _string(json['header']),
      // 和 MD3 的构造器默认值一致：缺少这个字段时开启
      enabledCookieJar = json.containsKey('enabledCookieJar') ? json['enabledCookieJar'] == true : true,
      concurrentRate = _string(json['concurrentRate']),
      bookUrlPattern = _string(json['bookUrlPattern']),
      searchUrl = _string(json['searchUrl']),
      jsLib = _string(json['jsLib']),
      loginUi = _string(json['loginUi']),
      loginCheckJs = _string(json['loginCheckJs']),
      ruleSearch = _group(json, 'ruleSearch'),
      ruleBookInfo = _group(json, 'ruleBookInfo'),
      ruleToc = _group(json, 'ruleToc'),
      ruleContent = _group(json, 'ruleContent');

  final Map<String, Object?> json;

  final String bookSourceUrl;
  final String bookSourceName;
  final BookSourceType bookSourceType;
  final String? header;
  final bool enabledCookieJar;
  final String? concurrentRate;
  final String? bookUrlPattern;
  final String? searchUrl;

  /// 书源共用的 JS（代码；JSON 对象形式按地址引用外部脚本，本引擎不支持）。
  final String? jsLib;

  /// 登录界面的定义（JSON 数组或 JS），`source.getLoginInfoMap` 用它取默认值。
  final String? loginUi;

  /// 每次链路请求得到响应后执行的 JS。
  final String? loginCheckJs;
  final RuleGroup ruleSearch;
  final RuleGroup ruleBookInfo;
  final RuleGroup ruleToc;
  final RuleGroup ruleContent;

  /// 导出为 JSON 对象，与导入时一致。
  Map<String, Object?> toJson() => json;

  static String? _string(Object? value) => value == null ? null : jsonText(value);

  // MD3 的 IntJsonDeserializer：不是数字时按默认值 0
  static int _int(Object? value) => value is num ? value.toInt() : 0;

  // MD3 的规则组反序列化：对象直接读，字符串按 JSON 解析，其余按空处理
  static RuleGroup _group(Map<String, Object?> json, String name) {
    var value = json[name];
    if (value is String) {
      try {
        value = parseLenientJson(value);
      } on FormatException {
        value = null;
      }
    }
    final rules = <String, String>{};
    if (value is Map<String, Object?>) {
      for (final MapEntry(:key, :value) in value.entries) {
        if (value != null) rules[key] = jsonText(value);
      }
    }
    return RuleGroup(name, rules);
  }
}

/// 被跳过的条目：在输入数组里的下标和原因。
typedef SkippedSource = ({int index, String reason});

/// 载入结果：可用的书源和被跳过的条目。
final class BookSourceLoadResult {
  const BookSourceLoadResult(this.sources, this.skipped);

  final List<BookSource> sources;
  final List<SkippedSource> skipped;
}

/// 载入书源 JSON：单个书源对象或书源数组。不是 JSON 对象的条目、没有书源地址的条目被跳过并报告原因。
/// 整个输入不是合法 JSON，或者顶层既不是对象也不是数组时，抛出 [FormatException]。
BookSourceLoadResult loadBookSources(String text) {
  // 去掉 UTF-8 BOM；MD3 用 Gson 宽松模式解析，严格解析失败时再按宽松语法解析
  final content = text.startsWith('﻿') ? text.substring(1) : text;
  Object? root;
  try {
    root = jsonDecode(content);
  } on FormatException {
    root = parseLenientJson(content);
  }
  final entries = switch (root) {
    List<Object?>() => root,
    Map<String, Object?>() => [root],
    _ => throw FormatException('顶层既不是书源数组也不是单个书源对象'),
  };

  final sources = <BookSource>[];
  final skipped = <SkippedSource>[];
  for (final (index, entry) in entries.indexed) {
    if (entry is! Map<String, Object?>) {
      skipped.add((index: index, reason: '不是 JSON 对象'));
    } else if (entry['bookSourceUrl'] case final String url when url.trim().isNotEmpty) {
      sources.add(BookSource._(entry));
    } else {
      skipped.add((index: index, reason: '缺少书源地址'));
    }
  }
  return BookSourceLoadResult(sources, skipped);
}
