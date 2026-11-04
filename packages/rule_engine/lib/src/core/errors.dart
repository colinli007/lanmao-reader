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

  /// 目录链路取到 0 章、正文链路取到空内容时的消息；书源校验据此区分「目录失效」「正文失效」。
  static const String tocEmpty = '目录为空';
  static const String contentEmpty = '正文为空';

  @override
  String get _kind => '规则错误';
}

/// 用到了本引擎不支持的 JS 用法，如 JSON 形式的 jsLib（按地址引用外部脚本）。
final class NeedsJsException extends RuleEngineException {
  NeedsJsException(super.message, {super.sourceName, super.field});

  @override
  String get _kind => '不支持的 JS 用法';
}

/// 书源 JS 出错：抛出了异常、语法错误、嵌套求值过深等。[message] 是 JS 的错误消息。
final class JsEvalException extends RuleEngineException {
  JsEvalException(super.message, {super.sourceName, super.field});

  @override
  String get _kind => 'JS 错误';
}

/// 书源 JS 调用了本引擎不支持的宿主 API（需要界面、WebView、设备、文件等）。[api] 是 API 名，如 `java.getVerificationCode`。
final class UnsupportedHostApiException extends RuleEngineException {
  UnsupportedHostApiException(super.message, {super.sourceName, super.field});

  String get api => message;

  @override
  String get _kind => '不支持的宿主 API';
}

/// 规则需要 WebView。[snippet] 是出错的规则片段。
final class NeedsWebViewException extends RuleEngineException {
  NeedsWebViewException(super.message, {super.sourceName, super.field});

  String get snippet => message;

  @override
  String get _kind => '需要 WebView';
}
