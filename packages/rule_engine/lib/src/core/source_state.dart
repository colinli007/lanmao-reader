/// worker 对书源级状态的一次读写。书源级状态（缓存、书源变量、登录头、登录信息、Cookie）在主 isolate 上只有一份，
/// 所有 worker 共用；worker 通过 [StoreRequest] 一次读写一项，由主 isolate 的 `RuleHost` 执行。
enum StoreOp {
  /// 读未过期的值，没有时为 null。
  get,

  /// 写入文本值；`saveSeconds` 大于 0 时到期失效，否则不过期。
  put,
  delete,

  /// 只在内存里的值（`cache.putMemory` 等），值是任意 JSON 值。
  getMemory,
  putMemory,
  deleteMemory,

  /// Cookie：键是地址，按注册域名归一（不是 http(s) 地址时整段文本就是键）。
  getCookie,

  /// 覆盖写入。
  setCookie,

  /// 按名合并写入。
  replaceCookie,
  removeCookie,
}

final class StoreRequest {
  const StoreRequest(this.op, this.key, {this.value, this.saveSeconds = 0});

  factory StoreRequest.fromJson(Map<String, Object?> json) => StoreRequest(
    StoreOp.values.byName(json['op'] as String),
    json['key'] as String,
    value: json['value'],
    saveSeconds: json['saveSeconds'] as int,
  );

  final StoreOp op;
  final String key;
  final Object? value;
  final int saveSeconds;

  Map<String, Object?> toJson() => {'op': op.name, 'key': key, 'value': value, 'saveSeconds': saveSeconds};

  @override
  String toString() => '${op.name} $key';
}

/// 书源 JS 写的调试日志（`java.log`、降级的 `toast`、请求头 JS 的错误），写入时就交给主 isolate 上的日志接收方。
final class SourceLog {
  const SourceLog({required this.sourceUrl, this.field, required this.message});

  factory SourceLog.fromJson(Map<String, Object?> json) =>
      SourceLog(sourceUrl: json['sourceUrl'] as String, field: json['field'] as String?, message: json['message'] as String);

  /// 书源地址。
  final String sourceUrl;

  /// 写日志时所在的字段，如 `ruleSearch.name`、`searchUrl`。
  final String? field;
  final String message;

  Map<String, Object?> toJson() => {'sourceUrl': sourceUrl, 'field': field, 'message': message};

  @override
  String toString() => '[$sourceUrl${field == null ? '' : ' $field'}] $message';
}
