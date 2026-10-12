/// 规则引擎的错误。链路把出错的书源名和字段补到错误上，提交方据此定位是哪个书源、哪条规则。
///
/// 这些错误会从 worker 传回主 isolate，所以只持有字符串。
sealed class RuleEngineException implements Exception {
  RuleEngineException(this.message, {this.sourceName, this.field});

  final String message;

  /// 书源名，由链路补上。
  String? sourceName;

  /// 出错的字段，如 `ruleToc.chapterName`，由链路补上。
  String? field;

  String get _kind;

  @override
  String toString() {
    final location = [?sourceName, ?field].join(' ');
    return '$_kind：$message${location.isEmpty ? '' : '（$location）'}';
  }
}

/// 规则本身有问题，或者按规则取不到必需的内容（详情 init、目录为空、正文为空等）。
final class RuleException extends RuleEngineException {
  RuleException(super.message, {super.sourceName, super.field});

  @override
  String get _kind => '规则错误';
}

/// 规则需要 JS 引擎。[snippet] 是出错的规则片段。
final class NeedsJsException extends RuleEngineException {
  NeedsJsException(super.message, {super.sourceName, super.field});

  String get snippet => message;

  @override
  String get _kind => '需要 JS 引擎';
}

/// 规则需要 WebView。[snippet] 是出错的规则片段。
final class NeedsWebViewException extends RuleEngineException {
  NeedsWebViewException(super.message, {super.sourceName, super.field});

  String get snippet => message;

  @override
  String get _kind => '需要 WebView';
}
