import '../core/environment.dart';
import '../core/errors.dart';
import '../net/java_url.dart';
import '../regex/java_replace.dart';
import '../text/html_unescape.dart';
import '../text/lenient_json.dart';
import 'analyze_by_json_path.dart';
import 'analyze_by_jsoup.dart';
import 'analyze_by_regex.dart';
import 'analyze_by_xpath.dart';
import 'content.dart';
import 'rule_data.dart';

/// 规则的取值语法。
enum RuleMode { xPath, json, jsoup, js, regex, webJs }

/// MD3 的 `AnalyzeRule`：对一份内容按规则取字符串、字符串列表和元素列表。
///
/// 照 MD3 源码移植，包括它的缓存和模式判定：规则按字符串缓存拆分结果，取值语法在第一次拆分时按当时的内容决定；
/// AllInOne 正则一旦出现，之后拆分的规则都按正则模板处理。需要 JS 或 WebView 的地方以对应的错误结束。
final class AnalyzeRule {
  AnalyzeRule(this.env, {RuleData? ruleData, this.chapter}) : ruleData = ruleData ?? ChainData();

  final RuleEnvironment env;

  /// `@put` 的存储：书籍或本次链路的临时数据。搜索列表里每一项换成这一项的书籍。
  RuleData ruleData;

  /// 当前章节（正文链路）。
  ChapterData? chapter;

  BookData? get book => ruleData is BookData ? ruleData as BookData : null;

  Object? _content;
  String? _baseUrl;
  JavaUrl? _redirectUrl;
  bool _isJson = false;
  bool _isRegex = false;

  AnalyzeByXPath? _xPath;
  AnalyzeByJSoup? _jsoup;
  AnalyzeByJsonPath? _jsonPath;

  final Map<String, List<_SourceRule>> _stringRuleCache = {};

  Object? get content => _content;

  /// 当前页面地址（`{{baseUrl}}`，地址规则取到空白时的结果）。
  String? get baseUrl => _baseUrl;

  /// 重定向之后的地址，相对地址按它拼接。
  JavaUrl? get redirectUrl => _redirectUrl;

  /// 设置内容。[content] 是字符串、元素、JSON 值或正则分组。
  AnalyzeRule setContent(Object? content, {String? baseUrl}) {
    // MD3 在这里抛 AssertionError
    if (content == null) throw RuleException('内容为空');
    _content = content;
    _isJson = isJsonContent(content);
    setBaseUrl(baseUrl);
    _xPath = null;
    _jsoup = null;
    _jsonPath = null;
    return this;
  }

  AnalyzeRule setBaseUrl(String? baseUrl) {
    if (baseUrl != null) _baseUrl = baseUrl;
    return this;
  }

  /// data 地址忽略，地址不合法时保留旧值。
  JavaUrl? setRedirectUrl(String url) {
    if (isDataUrl(url)) return _redirectUrl;
    _redirectUrl = JavaUrl.tryParse(url) ?? _redirectUrl;
    return _redirectUrl;
  }

  AnalyzeByXPath _analyzeByXPath(Object? o) =>
      identical(o, _content) ? (_xPath ??= AnalyzeByXPath(env, _content)) : AnalyzeByXPath(env, o);

  AnalyzeByJSoup _analyzeByJSoup(Object? o) =>
      identical(o, _content) ? (_jsoup ??= AnalyzeByJSoup(env, _content)) : AnalyzeByJSoup(env, o);

  AnalyzeByJsonPath _analyzeByJsonPath(Object? o) =>
      identical(o, _content) ? (_jsonPath ??= AnalyzeByJsonPath(_content)) : AnalyzeByJsonPath(o);

  // ---------------------------------------------------------------- 取值

  /// 取字符串列表。规则或内容为空时为 null。[isUrl] 时转成绝对地址，去掉空项并去重。
  List<String>? getStringList(String? rule, {Object? content, bool isUrl = false}) {
    if (rule == null || rule.isEmpty) return null;
    return _getStringList(_splitCached(rule), content: content, isUrl: isUrl);
  }

  List<String>? _getStringList(List<_SourceRule> ruleList, {Object? content, bool isUrl = false}) {
    Object? result;
    final current = content ?? _content;
    if (current != null && ruleList.isNotEmpty) {
      result = current;
      for (final sourceRule in ruleList) {
        _putRule(sourceRule.putMap);
        sourceRule.makeUpRule(result);
        if (result == null) continue;
        final rule = sourceRule.rule;
        if (rule.isNotEmpty) {
          result = switch (sourceRule.mode) {
            RuleMode.webJs => throw NeedsWebViewException(sourceRule.snippet),
            RuleMode.js => throw NeedsJsException(sourceRule.snippet),
            RuleMode.json => _analyzeByJsonPath(result).getStringList(rule),
            RuleMode.xPath => _analyzeByXPath(result).getStringList(rule),
            RuleMode.jsoup => _analyzeByJSoup(result).getStringList(rule),
            RuleMode.regex => rule,
          };
        }
        if (sourceRule.replaceRegex.isNotEmpty) {
          result = result is List
              ? [for (final item in result) _replaceRegex(contentToString(item), sourceRule)]
              : _replaceRegex(contentToString(result), sourceRule);
        }
      }
    }
    if (result == null) return null;
    if (result is String) result = result.split('\n');
    if (isUrl) {
      final urls = <String>[];
      if (result is List) {
        for (final url in result) {
          final absolute = absoluteUrl(_redirectUrl, contentToString(url));
          if (absolute.isNotEmpty && !urls.contains(absolute)) urls.add(absolute);
        }
      }
      return urls;
    }
    // 规则为空时结果是内容本身：只有字符串列表才能当结果
    return result is List ? [for (final item in result) contentToString(item)] : null;
  }

  /// 取字符串。规则为空时为空串。[isUrl] 时取第一项并转成绝对地址，取到空白时为 [baseUrl]。
  /// [unescape] 时反转义 HTML 实体（正文链路等格式化之后再反转义）。
  String getString(String? rule, {Object? content, bool isUrl = false, bool unescape = true}) {
    if (rule == null || rule.isEmpty) return '';
    return _getString(_splitCached(rule), content: content, isUrl: isUrl, unescape: unescape);
  }

  String _getString(List<_SourceRule> ruleList, {Object? content, bool isUrl = false, bool unescape = true}) {
    Object? result;
    final current = content ?? _content;
    if (current != null && ruleList.isNotEmpty) {
      result = current;
      for (final sourceRule in ruleList) {
        _putRule(sourceRule.putMap);
        sourceRule.makeUpRule(result);
        if (result == null) continue;
        final rule = sourceRule.rule;
        if (rule.trim().isNotEmpty || sourceRule.replaceRegex.isEmpty) {
          result = switch (sourceRule.mode) {
            RuleMode.webJs => throw NeedsWebViewException(sourceRule.snippet),
            RuleMode.js => throw NeedsJsException(sourceRule.snippet),
            RuleMode.json => _analyzeByJsonPath(result).getString(rule),
            RuleMode.xPath => _analyzeByXPath(result).getString(rule),
            RuleMode.jsoup =>
              isUrl ? _analyzeByJSoup(result).getString0(rule) : _analyzeByJSoup(result).getString(rule),
            RuleMode.regex => rule,
          };
        }
        if (result != null && sourceRule.replaceRegex.isNotEmpty) {
          result = _replaceRegex(contentToString(result), sourceRule);
        }
      }
    }
    final text = contentToString(result ?? '');
    final str = unescape && text.contains('&') ? unescapeHtml4(text) : text;
    if (isUrl) return str.trim().isEmpty ? (_baseUrl ?? '') : absoluteUrl(_redirectUrl, str);
    return str;
  }

  /// 预先拆分规则：取值语法按当前内容决定，之后换了内容也沿用（MD3 在列表项 setContent 之前拆好字段规则）。
  PreparedRule prepare(String? rule) => PreparedRule._(rule == null || rule.isEmpty ? const [] : _split(rule));

  String getStringOf(PreparedRule rule, {bool isUrl = false}) => _getString(rule._rules, isUrl: isUrl);

  List<String>? getStringListOf(PreparedRule rule, {bool isUrl = false}) => _getStringList(rule._rules, isUrl: isUrl);

  /// 取单个元素（详情的 `init` 规则）。规则以 `:` 开头时按 AllInOne 正则取第一个匹配。
  /// JSoup 和 XPath 的结果是列表（[ElementList]、[XPathNodeList]），取不到时是空列表而不是 null。
  Object? getElement(String rule) {
    if (rule.isEmpty) return null;
    Object? result;
    final current = _content;
    final ruleList = _split(rule, allInOne: true);
    if (current != null && ruleList.isNotEmpty) {
      result = current;
      for (final sourceRule in ruleList) {
        _putRule(sourceRule.putMap);
        sourceRule.makeUpRule(result);
        if (result == null) continue;
        final rule = sourceRule.rule;
        result = switch (sourceRule.mode) {
          RuleMode.regex => AnalyzeByRegex.getElement(env, contentToString(result), _splitNotBlank(rule)),
          RuleMode.webJs => throw NeedsWebViewException(sourceRule.snippet),
          RuleMode.js => throw NeedsJsException(sourceRule.snippet),
          RuleMode.json => _analyzeByJsonPath(result).getObject(rule),
          RuleMode.xPath => XPathNodeList(_analyzeByXPath(result).getElements(rule)),
          RuleMode.jsoup => ElementList(_analyzeByJSoup(result).getElements(rule)),
        };
        if (sourceRule.replaceRegex.isNotEmpty) result = _replaceRegex(contentToString(result), sourceRule);
      }
    }
    return result;
  }

  /// 取元素列表（各链路的列表规则）。规则以 `:` 开头时按 AllInOne 正则取全部匹配。
  /// 和 MD3 一样，这里不替换 `##`、`{{}}`、`@get`，规则原样交给解析器。
  List<Object> getElements(String rule) {
    Object? result;
    final current = _content;
    final ruleList = _split(rule, allInOne: true);
    if (current != null && ruleList.isNotEmpty) {
      result = current;
      for (final sourceRule in ruleList) {
        _putRule(sourceRule.putMap);
        if (result == null) continue;
        final rule = sourceRule.rule;
        result = switch (sourceRule.mode) {
          RuleMode.regex => AnalyzeByRegex.getElements(env, contentToString(result), _splitNotBlank(rule)),
          RuleMode.webJs => throw NeedsWebViewException(sourceRule.snippet),
          RuleMode.js => throw NeedsJsException(sourceRule.snippet),
          RuleMode.json => _analyzeByJsonPath(result).getList(rule),
          RuleMode.xPath => _analyzeByXPath(result).getElements(rule),
          RuleMode.jsoup => _analyzeByJSoup(result).getElements(rule),
        };
      }
    }
    if (result is List) return [for (final item in result) ?item];
    return [];
  }

  // ---------------------------------------------------------------- 变量

  void _putRule(Map<String, String> map) {
    for (final MapEntry(:key, :value) in map.entries) {
      put(key, getString(value));
    }
  }

  /// 写入第一个存在的存储：章节、书籍、本次链路。
  String put(String key, String value) {
    (chapter ?? ruleData).variables[key] = value;
    return value;
  }

  /// `bookName` 和 `title` 读书名和章节名；其余按章节、书籍、本次链路的顺序取第一个非空值，都没有时为空串。
  String get(String key) {
    if (key == 'bookName' && book != null) return book!.name;
    if (key == 'title' && chapter != null) return chapter!.title;
    for (final holder in [chapter, ruleData]) {
      final value = holder?.variables[key];
      if (value != null && value.isNotEmpty) return value;
    }
    return '';
  }

  // ---------------------------------------------------------------- 拆分

  List<_SourceRule> _splitCached(String rule) => _stringRuleCache.putIfAbsent(rule, () => _split(rule));

  /// `{{}}` 里的内嵌规则：和 [getString] 共用缓存，缓存满 16 条后不再写入（MD3 的 getOrPutLimit）。
  List<_SourceRule> _singleRuleCached(String rule) {
    final cached = _stringRuleCache[rule];
    if (cached != null) return cached;
    final created = [_SourceRule(this, rule)];
    if (_stringRuleCache.length < 16) _stringRuleCache[rule] = created;
    return created;
  }

  static final RegExp _jsPattern = RegExp(r'<js>([\w\W]*?)</js>|@js:([\w\W]*)', caseSensitive: false);
  static final RegExp _webJsPattern = RegExp(r'@webjs:([\w\W]{5,})', caseSensitive: false);

  /// 先按 JS 片段切段，各段之间是管道：上一段的结果是下一段的输入。
  List<_SourceRule> _split(String ruleStr, {bool allInOne = false}) {
    if (ruleStr.isEmpty) return [];
    final ruleList = <_SourceRule>[];
    var mode = RuleMode.jsoup;
    var start = 0;
    if (allInOne && ruleStr.startsWith(':')) {
      mode = RuleMode.regex;
      _isRegex = true;
      start = 1;
    } else if (_isRegex) {
      mode = RuleMode.regex;
    }
    void addPlain(int end) {
      if (end <= start) return;
      final tmp = _trimJava(ruleStr.substring(start, end));
      if (tmp.isNotEmpty) ruleList.add(_SourceRule(this, tmp, mode));
    }

    for (final match in _jsPattern.allMatches(ruleStr)) {
      addPlain(match.start);
      final code = match.group(2) ?? '';
      ruleList.add(_SourceRule(this, code.isEmpty ? match.group(1) ?? '' : code, RuleMode.js, match.group(0)));
      start = match.end;
    }
    for (final match in _webJsPattern.allMatches(ruleStr)) {
      addPlain(match.start);
      ruleList.add(_SourceRule(this, match.group(1)!, RuleMode.webJs, match.group(0)));
      start = match.end;
    }
    if (ruleStr.length > start) addPlain(ruleStr.length);
    return ruleList;
  }

  String _replaceRegex(String result, _SourceRule rule) =>
      replaceByRule(env, result, rule.replaceRegex, rule.replacement, firstOnly: rule.replaceFirst);

  static List<String> _splitNotBlank(String rule) => [
    for (final part in rule.split('&&'))
      if (part.trim().isNotEmpty) part.trim(),
  ];
}

/// 预先拆分好的规则，见 [AnalyzeRule.prepare]。
final class PreparedRule {
  const PreparedRule._(this._rules);

  final List<_SourceRule> _rules;
}

/// MD3 的 `AnalyzeRule.SourceRule`：一段规则，拆出取值语法、`@put`、`@get`、`{{}}`、`$n` 和 `##` 替换。
final class _SourceRule {
  _SourceRule(this._owner, String ruleStr, [this.mode = RuleMode.jsoup, String? snippet]) : snippet = snippet ?? ruleStr {
    var text = ruleStr;
    if (mode != RuleMode.js && mode != RuleMode.regex) {
      final lower = ruleStr.toLowerCase();
      if (lower.startsWith('@css:')) {
        mode = RuleMode.jsoup;
      } else if (ruleStr.startsWith('@@')) {
        mode = RuleMode.jsoup;
        text = ruleStr.substring(2);
      } else if (lower.startsWith('@xpath:')) {
        mode = RuleMode.xPath;
        text = ruleStr.substring(7);
      } else if (lower.startsWith('@json:')) {
        mode = RuleMode.json;
        text = ruleStr.substring(6);
      } else if (_owner._isJson || ruleStr.startsWith(r'$.') || ruleStr.startsWith(r'$[')) {
        mode = RuleMode.json;
      } else if (ruleStr.startsWith('/')) {
        mode = RuleMode.xPath;
      }
    }
    rule = _splitPutRule(text);

    // @get、{{}}：出现在开头，或者前面没有 ## 时，整条规则变成模板
    final first = _evalPattern.firstMatch(rule);
    if (first != null &&
        mode != RuleMode.js &&
        mode != RuleMode.regex &&
        (first.start == 0 || !rule.substring(0, first.start).contains('##'))) {
      mode = RuleMode.regex;
    }
    var start = 0;
    for (final match in _evalPattern.allMatches(rule)) {
      if (match.start > start) _splitRegex(rule.substring(start, match.start));
      final tmp = match.group(0)!;
      if (tmp.toLowerCase().startsWith('@get:')) {
        _ruleType.add(_getRuleType);
        _ruleParam.add(tmp.substring(6, tmp.length - 1));
      } else if (tmp.startsWith('{{')) {
        _ruleType.add(_jsRuleType);
        _ruleParam.add(tmp.substring(2, tmp.length - 2));
      } else {
        _splitRegex(tmp);
      }
      start = match.end;
    }
    if (rule.length > start) _splitRegex(rule.substring(start));
  }

  final AnalyzeRule _owner;

  /// 规则在原文里的样子，用于「需要 JS」「需要 WebView」的错误信息。
  final String snippet;
  RuleMode mode;
  late String rule;
  String replaceRegex = '';
  String replacement = '';
  bool replaceFirst = false;
  final Map<String, String> putMap = {};
  final List<String> _ruleParam = [];
  final List<int> _ruleType = [];

  static const int _getRuleType = -2;
  static const int _jsRuleType = -1;
  static const int _defaultRuleType = 0;

  static final RegExp _putPattern = RegExp(r'@put:(\{[^}]+?\})', caseSensitive: false);
  static final RegExp _evalPattern = RegExp(r'@get:\{[^}]+?\}|\{\{[\w\W]*?\}\}', caseSensitive: false);
  static final RegExp _regexPattern = RegExp(r'\$\d{1,2}');

  /// 取出 `@put:{键:规则}`（严格或宽松 JSON），并从规则里删掉。
  String _splitPutRule(String ruleStr) {
    var result = ruleStr;
    for (final match in _putPattern.allMatches(ruleStr)) {
      result = result.replaceAll(match.group(0)!, '');
      try {
        putMap.addAll(parseLenientStringMap(match.group(1)!));
      } on FormatException {
        // MD3 解析失败时忽略这个 @put
      }
    }
    return result;
  }

  /// 拆出 `$n`（只看 `##` 之前的部分）。
  void _splitRegex(String ruleStr) {
    final head = ruleStr.split('##').first;
    if (_regexPattern.hasMatch(head) && mode != RuleMode.js && mode != RuleMode.regex) mode = RuleMode.regex;
    var start = 0;
    for (final match in _regexPattern.allMatches(head)) {
      if (match.start > start) {
        _ruleType.add(_defaultRuleType);
        _ruleParam.add(ruleStr.substring(start, match.start));
      }
      final tmp = match.group(0)!;
      // $0 的类型码等于字面量，按原样保留
      _ruleType.add(int.parse(tmp.substring(1)));
      _ruleParam.add(tmp);
      start = match.end;
    }
    if (ruleStr.length > start) {
      _ruleType.add(_defaultRuleType);
      _ruleParam.add(ruleStr.substring(start));
    }
  }

  /// 替换 `@get`、`{{}}`、`$n` 拼出规则，再拆出 `##` 替换。
  void makeUpRule(Object? result) {
    if (_ruleParam.isNotEmpty) {
      // 和 MD3 一样从后往前求值，结果按原顺序拼接
      final parts = List.filled(_ruleParam.length, '');
      for (var index = _ruleParam.length - 1; index >= 0; index--) {
        final type = _ruleType[index];
        final param = _ruleParam[index];
        if (type > _defaultRuleType) {
          final groups = switch (result) {
            RegexMatchGroups() => result.groups,
            List() => result,
            _ => null,
          };
          if (groups == null) {
            parts[index] = param;
          } else if (groups.length > type && groups[type] != null) {
            parts[index] = contentToString(groups[type]);
          }
        } else if (type == _jsRuleType) {
          parts[index] = _evalInner(param);
        } else if (type == _getRuleType) {
          parts[index] = _owner.get(param);
        } else {
          parts[index] = param;
        }
      }
      rule = parts.join();
    }
    final parts = rule.split('##');
    rule = parts[0].trim();
    if (parts.length > 1) replaceRegex = parts[1];
    if (parts.length > 2) replacement = parts[2];
    if (parts.length > 3) replaceFirst = true;
  }

  /// `{{x}}`：x 是规则时对当前内容求值；`baseUrl`、`title` 直接取值；其余需要 JS。
  String _evalInner(String param) {
    if (param.startsWith('@') || param.startsWith(r'$.') || param.startsWith(r'$[') || param.startsWith('//')) {
      return _owner._getString(_owner._singleRuleCached(param));
    }
    return switch (param.trim()) {
      'baseUrl' => _owner.baseUrl ?? '',
      'title' => _owner.chapter?.title ?? '',
      _ => throw NeedsJsException('{{$param}}'),
    };
  }
}

/// Kotlin 的 `trim { it <= ' ' }`。
String _trimJava(String text) {
  var start = 0;
  var end = text.length;
  while (start < end && text.codeUnitAt(start) <= 0x20) {
    start++;
  }
  while (end > start && text.codeUnitAt(end - 1) <= 0x20) {
    end--;
  }
  return text.substring(start, end);
}
