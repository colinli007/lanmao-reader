import '../js/js_values.dart';
import '../source/book_source.dart';
import '../text/lenient_json.dart';
import 'environment.dart';
import 'errors.dart';

/// 一次链路调用（一个任务）里和书源有关的状态：环境、书源，以及只在这个任务里有效的副本和对象。
///
/// 书源级状态（缓存、书源变量、登录头、登录信息、Cookie）的正本在主 isolate 上，这里经 [RuleEnvironment.store] 读写；
/// 登录头要叠加到每个请求里，所以第一次用到时取一次，任务里写入时同步更新本地副本。
final class SourceTask {
  SourceTask(this.env, this.source);

  final RuleEnvironment env;
  final BookSource source;

  /// 书源的键（书源地址）：书源级状态按它分开存放。
  String get sourceKey => source.bookSourceUrl;

  /// 交给 JS 的 Dart 对象（元素、响应、加密器），随任务结束失效。
  final HandleTable handles = HandleTable();

  /// 正在求值的字段，如 `ruleSearch.name`：JS 的日志带上它。
  String? field;

  /// 在字段 [name] 上执行：期间 [field] 是它；出错时没有字段的错误补上它。
  T inField<T>(String name, T Function() body) {
    final saved = field;
    field = name;
    try {
      return body();
    } on RuleEngineException catch (e) {
      e.field ??= name;
      rethrow;
    } finally {
      field = saved;
    }
  }

  // ---------------------------------------------------------------- 书源级状态

  /// 键的前缀与 MD3 的 `CacheManager` 用法一致。
  String get variableKeyPrefix => 'v_${sourceKey}_';
  String get sourceVariableKey => 'sourceVariable_$sourceKey';
  String get loginHeaderKey => 'loginHeader_$sourceKey';
  String get loginInfoKey => 'userInfo_$sourceKey';

  String? storeGet(String key) => env.store(StoreRequest(StoreOp.get, key)) as String?;

  void storePut(String key, String value, {int saveSeconds = 0}) =>
      env.store(StoreRequest(StoreOp.put, key, value: value, saveSeconds: saveSeconds));

  void storeDelete(String key) => env.store(StoreRequest(StoreOp.delete, key));

  // ---------------------------------------------------------------- 登录头

  bool _loginHeaderLoaded = false;
  String? _loginHeader;

  /// 登录头原文（JSON），没有时为 null。
  String? get loginHeader {
    if (!_loginHeaderLoaded) {
      _loginHeader = storeGet(loginHeaderKey);
      _loginHeaderLoaded = true;
    }
    return _loginHeader;
  }

  /// 登录头按严格或宽松 JSON 解析成的请求头，没有或不是 JSON 对象时为 null。
  Map<String, String>? get loginHeaderMap {
    final header = loginHeader;
    if (header == null) return null;
    try {
      return parseLenientStringMap(header);
    } on FormatException {
      return null;
    }
  }

  /// 保存登录头：原文照存（不是 JSON 也照存）；其中有 `Cookie` 或 `cookie` 时按名合并进书源域名的 Cookie。
  void putLoginHeader(String header) {
    _loginHeader = header;
    _loginHeaderLoaded = true;
    final cookie = loginHeaderMap?['Cookie'] ?? loginHeaderMap?['cookie'];
    if (cookie != null) env.store(StoreRequest(StoreOp.replaceCookie, sourceKey, value: cookie));
    storePut(loginHeaderKey, header);
  }

  /// 删除登录头，同时删除书源域名的 Cookie。
  void removeLoginHeader() {
    _loginHeader = null;
    _loginHeaderLoaded = true;
    storeDelete(loginHeaderKey);
    env.store(StoreRequest(StoreOp.removeCookie, sourceKey));
  }

  // ---------------------------------------------------------------- 日志

  void log(String message, {String? field}) =>
      env.log(SourceLog(sourceUrl: sourceKey, field: field ?? this.field, message: message));
}
