import 'dart:convert';
import 'dart:typed_data';

import 'package:html/dom.dart';

import '../chain/formatter.dart';
import '../chain/models.dart';
import '../core/environment.dart';
import '../core/errors.dart';
import '../core/source_task.dart';
import '../host/cookie_store.dart' show cookieToMap, mapToCookie;
import '../html/css_selector.dart';
import '../html/jsoup_text.dart';
import '../html/jsoup_entities.dart';
import '../request/analyze_url.dart';
import '../request/str_response.dart';
import '../rule/analyze_rule.dart';
import '../rule/content.dart';
import '../text/charsets.dart';
import '../text/lenient_json.dart';
import 'codec.dart';
import 'crypto.dart';
import 'java_rsa.dart';
import 'js_values.dart';
import 'source_js.dart';
import 'time_text.dart';

/// 注入书源 JS 的宿主 API：`__host.call(api, args)` 按名字分发到这里，同名 API 按求值帧的种类选实现。
/// 语义照 MD3（legado-with-MD3 d1b488b），见 `openspec/changes/add-js-runtime/research/md3-host-api.md`。
///
/// 实参是 JS 交来的值（[fromJsValue] 的结果），返回值交给 [toJsValue]。普通异常在 JS 里可以被 try/catch；
/// [UnsupportedHostApiException] 等不可捕获（见 [SourceJs.isFatal]）。
Object? callHostApi(SourceJs js, JsFrame frame, String api, List<Object?> args) {
  final handler = _apis[api] ?? (throw JsEvalException('没有这个宿主 API：$api'));
  return handler(_Call(js, frame, args));
}

final class _Call {
  _Call(this.js, this.frame, this.args);

  final SourceJs js;
  final JsFrame frame;
  final List<Object?> args;

  SourceTask get task => frame.task;

  RuleEnvironment get env => frame.task.env;

  int get length => args.length;

  Object? operator [](int index) => index < args.length ? args[index] : null;

  /// Kotlin 的非空 String 参数：传 null（或没传）时出错，其余按 JS 的 `String()` 转成文本。
  String str(int index) {
    final value = this[index];
    if (value == null) throw ArgumentError('第 ${index + 1} 个参数不能为 null');
    return _text(value);
  }

  String? optStr(int index) {
    final value = this[index];
    return value == null ? null : _text(value);
  }

  /// JS 数字转 Java 的 int/long：截断小数。
  int integer(int index, [int fallback = 0]) => switch (this[index]) {
    final int value => value,
    final JsNumber value => value.value.isFinite ? value.value.truncate() : 0,
    final String value => num.tryParse(value.trim())?.truncate() ?? 0,
    _ => fallback,
  };

  /// 字节数组参数：JS 数组（-128 到 127）或文本（按 UTF-8）。
  Uint8List bytes(int index) => jsBytes(this[index]);

  SymmetricCrypto cipher() => task.handles.get<_Cipher>(this[0] as int).crypto;

  StrResponse response() => task.handles.get<StrResponse>(this[0] as int);

  Node element() => task.handles.get<Node>(this[0] as int);

  List<Node> elements() => [for (final id in this[0] as List) task.handles.get<Node>(id as int)];
}

String _text(Object value) => switch (value) {
  String() => value,
  Node() => contentToString(value),
  _ => jsString(value),
};

/// JS 交来的字节数组（-128 到 127 的数组，或按 UTF-8 编码的文本）转成字节；宿主 API 的参数和 `imageDecode` 的返回值都用它。
Uint8List jsBytes(Object? value) => switch (value) {
  Uint8List() => value,
  List() => Uint8List.fromList([for (final b in value) (b as num).toInt() & 0xFF]),
  String() => Uint8List.fromList(utf8.encode(value)),
  null => throw ArgumentError('字节数组不能为 null'),
  _ => throw ArgumentError('不是字节数组：${_text(value)}'),
};

/// 加密器对象：通过句柄交给 JS。
final class _Cipher implements JsHandle {
  _Cipher(this.crypto);

  final SymmetricCrypto crypto;

  @override
  String get jsType => 'cipher';
}

typedef _Api = Object? Function(_Call call);

final Map<String, _Api> _apis = {
  ..._variableApis,
  ..._networkApis,
  ..._responseApis,
  ..._ruleApis,
  ..._elementApis,
  ..._jsoupApis,
  ..._codecApis,
  ..._cryptoApis,
  ..._textApis,
  ..._logApis,
  ..._cookieApis,
  ..._cacheApis,
  ..._sourceApis,
  ..._bookApis,
  'javaClass.digest': (c) => digest(c.str(0), c.bytes(1)),
  'javaClass.base64Decode': (c) => base64DecodeJava(c.str(0)),
  'javaClass.randomIv': (c) => javaCipherRandomIv(),
  'javaClass.rsaPrivateKey': (c) => javaRsaPrivateKey(c.bytes(0)),
  'javaClass.rsaSign': (c) => javaRsaSign(c.bytes(0), c.bytes(1)),
  'javaClass.cipher': (c) => javaAesCipher(
    c.str(0),
    c.bytes(1),
    c[2] == null ? null : c.bytes(2),
    c.integer(3),
    c.bytes(4),
  ),
  'unsupported': (c) => throw UnsupportedHostApiException(c.str(0)),
};

// ---------------------------------------------------------------- 变量

/// `java.put`、`java.get`：规则、URL、书源三种上下文写读的地方不同；`source.put`、`source.get` 总是书源级变量。
/// `get` 有两个以上参数时是直连 GET 请求。
final Map<String, _Api> _variableApis = {
  'put': (c) {
    final key = c.str(0);
    final text = _putValue(c);
    return switch (c.frame) {
      RuleFrame(:final rule) => rule.put(key, text),
      UrlFrame(:final request) => request.put(key, text),
      _ => _sourcePut(c.task, key, text),
    };
  },
  'get': (c) {
    if (c.length >= 2) return _directGet(c);
    final key = c.str(0);
    return switch (c.frame) {
      RuleFrame(:final rule) => rule.get(key),
      UrlFrame(:final request) => request.get(key),
      _ => _sourceGet(c.task, key),
    };
  },
  'source.put': (c) => _sourcePut(c.task, c.str(0), _putValue(c)),
  'source.get': (c) => c.length >= 2 ? _directGet(c) : _sourceGet(c.task, c.str(0)),
};

String _putValue(_Call c) {
  final value = c[1];
  if (value == null) throw ArgumentError('put 的值不能为 null');
  return _text(value);
}

Object? _directGet(_Call c) => _direct(c, 'GET', url: c.str(0), headers: c[1], timeout: c[2]);

String _sourcePut(SourceTask task, String key, String value) {
  task.storePut('${task.variableKeyPrefix}$key', value);
  return value;
}

String _sourceGet(SourceTask task, String key) => task.storeGet('${task.variableKeyPrefix}$key') ?? '';

// ---------------------------------------------------------------- 网络

final Map<String, _Api> _networkApis = {
  // URL 规则构造请求，返回正文；出错时不抛出，返回错误的描述
  'ajax': (c) {
    final arg = c[0];
    final url = arg is List ? (arg.isEmpty ? 'null' : _text(arg.first ?? 'null')) : c.str(0);
    try {
      return _request(c, url, timeout: c[1]).fetch().body;
    } catch (e) {
      if (SourceJs.isFatal(e)) rethrow;
      c.env.checkCancelled();
      c.task.log('ajax($url) error\n$e');
      return '$e';
    }
  },
  'ajaxAll': (c) {
    final urls = [for (final url in c[0] as List) _text(url ?? 'null')];
    final requests = [for (final url in urls) _request(c, url)];
    c.env.checkCancelled();
    final results = c.env.fetchAll([for (final request in requests) request.http]);
    return [for (final (index, result) in results.indexed) requests[index].response(result)];
  },
  // 返回响应对象；请求头参数是 JSON 时整体替换书源请求头和登录头；出错时返回状态码 200、正文为错误描述的响应
  'connect': (c) {
    final url = c.str(0);
    Map<String, String>? headers;
    final header = c.optStr(1);
    if (header != null) {
      try {
        headers = parseLenientStringMap(header);
      } on FormatException {
        headers = null;
      }
    }
    try {
      return _request(c, url, headers: headers, timeout: c[2]).fetch();
    } catch (e) {
      if (SourceJs.isFatal(e)) rethrow;
      c.env.checkCancelled();
      c.task.log('connect($url) error\n$e');
      return StrResponse.error(url, '$e');
    }
  },
  'post': (c) => _direct(c, 'POST', url: c.str(0), body: c.str(1), headers: c[2], timeout: c[3]),
  'head': (c) => _direct(c, 'HEAD', url: c.str(0), headers: c[1], timeout: c[2]),
  'getStrResponse': (c) => _urlRequest(c).fetch(),
  'initUrl': (c) {
    _urlRequest(c).initUrl();
    return null;
  },
  'urlJava.url': (c) => _urlRequest(c).url,
  'urlJava.ruleUrl': (c) => _urlRequest(c).ruleUrl,
  'headerMap.put': (c) => _urlRequest(c).headers[c.str(0)] = c.str(1),
  'headerMap.get': (c) => _urlRequest(c).headers[c.str(0)],
  'headerMap.remove': (c) => _urlRequest(c).headers.remove(c.str(0)),
  'headerMap.containsKey': (c) => _urlRequest(c).headers.containsKey(c.str(0)),
  'headerMap.putAll': (c) {
    final map = c[0];
    if (map is Map) {
      for (final MapEntry(:key, :value) in map.entries) {
        _urlRequest(c).headers['$key'] = _text(value ?? 'null');
      }
    }
    return null;
  },
};

SourceRequest _urlRequest(_Call c) => switch (c.frame) {
  UrlFrame(:final request) => request,
  _ => throw JsEvalException('只能在 URL 的 JS 里调用'),
};

/// `java.ajax`、`java.connect` 等用 URL 规则构造的请求：不补全相对地址。规则上下文里带上当前书籍（MD3 的 AnalyzeRule.ajax）。
SourceRequest _request(_Call c, String url, {Map<String, String>? headers, Object? timeout}) {
  final ms = timeout is num ? timeout.toInt() : (timeout is JsNumber ? timeout.value.toInt() : null);
  return SourceRequest(
    c.task,
    url,
    ruleData: c.frame is RuleFrame ? (c.frame as RuleFrame).rule.book : null,
    headers: headers,
    timeout: ms == null || ms <= 0 ? null : Duration(milliseconds: ms),
  );
}

/// Jsoup 的默认 User-Agent（`java.get/post/head` 没给 UA 时）。
const String _jsoupUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/53.0.2785.143 Safari/537.36';

/// `java.get/post/head`：MD3 用 Jsoup 直连，不解析 URL 选项，不带书源请求头、登录头和 Cookie，不跟随重定向，
/// 默认 30 秒超时，状态码大于等于 400 时出错。
StrResponse _direct(_Call c, String method, {required String url, String? body, Object? headers, Object? timeout}) {
  final requestHeaders = <String, String>{
    if (headers is Map)
      for (final MapEntry(:key, :value) in headers.entries) '$key': _text(value ?? 'null'),
  };
  if (!requestHeaders.keys.any((name) => name.toLowerCase() == 'user-agent')) {
    requestHeaders['User-Agent'] = _jsoupUserAgent;
  }
  if (body != null && !requestHeaders.keys.any((name) => name.toLowerCase() == 'content-type')) {
    requestHeaders['Content-Type'] = 'application/x-www-form-urlencoded; charset=UTF-8';
  }
  final ms = timeout is num ? timeout.toInt() : null;
  c.env.checkCancelled();
  final result = c.env.fetch(
    HttpRequest(
      url: url,
      method: method,
      headers: requestHeaders,
      body: body,
      sourceUrl: c.task.sourceKey,
      concurrentRate: c.task.source.concurrentRate,
      direct: true,
      timeout: ms == null || ms <= 0 ? null : Duration(milliseconds: ms),
    ),
  );
  return StrResponse(
    url: result.url,
    body: _jsoupBody(result),
    statusCode: result.statusCode,
    headers: result.headers,
    setCookies: result.setCookies,
  );
}

/// Jsoup 的 `Response.body()`：按 Content-Type 的 charset 解码，没有时按 UTF-8。
String _jsoupBody(HttpResult result) {
  final contentType = result.headers['content-type'] ?? '';
  final match = RegExp(r'charset=\s*"?([^\s;"]*)', caseSensitive: false).firstMatch(contentType);
  final encoding = match == null ? null : charsetByName(match.group(1)!);
  return decodeLikeJava(result.body, encoding ?? utf8);
}

// ---------------------------------------------------------------- 响应对象

final Map<String, _Api> _responseApis = {
  'res.create': (c) => StrResponse.fromUrl(c.str(0), c.optStr(1)),
  'res.body': (c) => c.response().body,
  'res.code': (c) => c.response().statusCode,
  'res.statusCode': (c) => c.response().statusCode,
  'res.message': (c) => c.response().message,
  'res.url': (c) => c.response().url,
  // headers(名) 是 OkHttp 的 Response.headers(name)：这个响应头的全部值（fix-md3-diff-findings 设计 D2）
  'res.headers': (c) => switch (c.optStr(1)) {
    null => c.response().headers,
    final name when name.toLowerCase() == 'set-cookie' => c.response().setCookies,
    final name => [?c.response().header(name)],
  },
  'res.header': (c) => c.response().header(c.str(1)),
  'res.cookies': (c) => c.response().cookies,
  'res.isSuccessful': (c) => c.response().isSuccessful,
  'res.callTime': (c) => 0,
};

// ---------------------------------------------------------------- 回调规则（规则上下文）

final Map<String, _Api> _ruleApis = {
  // getString(规则[, 内容[, 是否地址]])，或 getString(规则, 是否反转义)
  'getString': (c) {
    final rule = _rule(c);
    final second = c[1];
    if (second is bool) return rule.getString(c.optStr(0), unescape: second);
    return rule.getString(c.optStr(0), content: second, isUrl: c[2] == true);
  },
  'getStringList': (c) => _rule(c).getStringList(c.optStr(0), content: c[1], isUrl: c[2] == true),
  'getElement': (c) {
    final rule = c.optStr(0);
    return rule == null ? null : _rule(c).getElement(rule);
  },
  'getElements': (c) {
    final list = _rule(c).getElements(c.optStr(0) ?? '');
    return list.every((item) => item is Node) ? ElementList(list.cast<Node>()) : list;
  },
  'setContent': (c) {
    final content = c[0];
    if (content == null) throw ArgumentError('内容不可空');
    _rule(c).setContent(content, baseUrl: c.optStr(1));
    return {hostObjectTag: 'ruleJava'};
  },
};

AnalyzeRule _rule(_Call c) => switch (c.frame) {
  RuleFrame(:final rule) => rule,
  _ => throw JsEvalException('只能在规则的 JS 里调用'),
};

// ---------------------------------------------------------------- 元素

final Map<String, _Api> _elementApis = {
  'el.text': (c) => jsoupText(c.element()),
  'el.ownText': (c) => jsoupOwnText(c.element()),
  'el.html': (c) => jsoupInnerHtml(c.element()),
  'el.data': (c) => jsoupData(c.element()),
  'el.outerHtml': (c) => jsoupOuterHtml(c.element()),
  'el.attr': (c) => jsoupAttr(c.element(), c.str(1)),
  'el.hasAttr': (c) => _hasAttr(c.element(), c.str(1)),
  'el.hasClass': (c) => jsoupHasClass(c.element(), c.str(1)),
  'el.id': (c) => jsoupAttr(c.element(), 'id'),
  'el.tagName': (c) => jsoupTagName(c.element()),
  'el.select': (c) => ElementList(CssSelector.parse(c.str(1)).select(c.env, c.element())),
  'el.selectFirst': (c) => CssSelector.parse(c.str(1)).select(c.env, c.element()).firstOrNull,
  'el.children': (c) => ElementList([...c.element().nodes.whereType<Element>()]),
  'el.parent': (c) => switch (c.element().parentNode) {
    final Element parent => parent,
    _ => null,
  },
  'el.parentNode': (c) => c.element().parentNode,
  // jsoup 的 getAllElements：自己和全部后代元素，先序（fix-md3-diff-findings 设计 D4）
  'el.getAllElements': (c) => ElementList(_selfAndDescendants(c.element())),
  'el.remove': (c) {
    c.element().remove();
    return null;
  },
  // jsoup Elements：text 用空格连接（跳过开头的空文本），html 用换行连接，attr 取第一个有这个属性的元素
  'els.text': (c) => _joinNonEmptyStart(c.elements().map(jsoupText), ' '),
  'els.html': (c) => _joinNonEmptyStart(c.elements().map(jsoupInnerHtml), '\n'),
  'els.outerHtml': (c) => jsoupOuterHtmlAll(c.elements()),
  'els.attr': (c) {
    final name = c.str(1);
    for (final element in c.elements()) {
      if (_hasAttr(element, name)) return jsoupAttr(element, name);
    }
    return '';
  },
  'els.select': (c) => ElementList(CssSelector.parse(c.str(1)).selectAll(c.env, c.elements())),
  'els.eq': (c) {
    final list = c.elements();
    final index = c.integer(1);
    return ElementList(index >= 0 && index < list.length ? [list[index]] : []);
  },
  'els.hasClass': (c) => c.elements().any((element) => jsoupHasClass(element, c.str(1))),
  'els.hasAttr': (c) => c.elements().any((element) => _hasAttr(element, c.str(1))),
  'els.eachText': (c) => [
    for (final element in c.elements())
      if (_hasText(element)) jsoupText(element),
  ],
  'els.eachAttr': (c) => [
    for (final element in c.elements())
      if (_hasAttr(element, c.str(1))) jsoupAttr(element, c.str(1)),
  ],
  'els.remove': (c) {
    for (final element in c.elements()) {
      element.remove();
    }
    return null;
  },
  'els.first': (c) => c.elements().firstOrNull,
  'els.last': (c) => c.elements().lastOrNull,
};

/// `org.jsoup.Jsoup`（source-js-api「Jsoup」）：解析成文档，用现有的 jsoup 兼容实现（add-rhino-compat 设计 D1）。
final Map<String, _Api> _jsoupApis = {
  'jsoup.unescapeEntities': (c) => unescapeJsoupEntities(c.str(0), c[1] == true),
  'jsoup.parse': (c) => parseJsoupDocument(c.str(0), baseUri: c.optStr(1)),
  'jsoup.parseBodyFragment': (c) => parseJsoupDocument(c.str(0)),
};

List<Node> _selfAndDescendants(Node root) {
  final out = <Node>[];
  void visit(Node node) {
    out.add(node);
    node.nodes.whereType<Element>().forEach(visit);
  }

  visit(root);
  return out;
}

/// jsoup 的 StringBuilder 拼接：已有内容时才加分隔符，所以开头的空串不留下分隔符。
String _joinNonEmptyStart(Iterable<String> parts, String separator) {
  final out = StringBuffer();
  for (final part in parts) {
    if (out.isNotEmpty) out.write(separator);
    out.write(part);
  }
  return out.toString();
}

/// `getWebViewUA()`：MD3 返回系统 WebView 的 UA，我们没有 WebView，用一个固定的 Android WebView UA（add-rhino-compat 设计 D5）。
const String webViewUserAgent =
    'Mozilla/5.0 (Linux; Android 14; Pixel 8 Build/AP2A.240805.005; wv) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Version/4.0 Chrome/131.0.6778.135 Mobile Safari/537.36';

/// jsoup 的 `Element.hasText`：有非空白的文本（`Elements.eachText` 只取这样的元素）。
bool _hasText(Node node) => jsoupText(node).trim().isNotEmpty;

/// jsoup 的 `hasAttr`：属性名不区分大小写；`abs:` 前缀要求能转成非空的绝对地址。
bool _hasAttr(Node node, String name) {
  if (node is! Element) return false;
  final lower = name.toLowerCase();
  if (lower.startsWith('abs:')) {
    final key = lower.substring(4);
    return node.attributes.keys.any((k) => '$k'.toLowerCase() == key) && jsoupAttr(node, name).isNotEmpty;
  }
  return node.attributes.keys.any((k) => '$k'.toLowerCase() == lower);
}

// ---------------------------------------------------------------- 编码

final Map<String, _Api> _codecApis = {
  // base64Decode(文本)、base64Decode(文本, 字符集) 用 Hutool 的宽松解码，base64Decode(文本, flags) 用 Android 的严格解码
  'base64Decode': (c) {
    final second = c[1];
    if (second is int) return bytesToString(base64DecodeAndroid(c.str(0), second), 'UTF-8');
    final text = c.optStr(0);
    if (text == null) return '';
    return bytesToString(base64DecodeLenient(text), second == null ? 'UTF-8' : _text(second));
  },
  'base64DecodeToByteArray': (c) {
    final text = c.optStr(0);
    if (text == null || text.trim().isEmpty) return null;
    return base64DecodeAndroid(text, c.integer(1));
  },
  'base64Encode': (c) => base64EncodeAndroid(utf8.encode(c.str(0)), c.length > 1 ? c.integer(1) : base64NoWrap),
  'hexDecodeToByteArray': (c) => hexDecode(c.str(0)),
  'hexDecodeToString': (c) => bytesToString(hexDecode(c.str(0)), 'UTF-8'),
  'hexEncodeToString': (c) => hexEncode(utf8.encode(c.str(0))),
  'strToBytes': (c) => stringToBytes(c.str(0), c.optStr(1) ?? 'UTF-8'),
  'bytesToStr': (c) => bytesToString(c.bytes(0), c.optStr(1) ?? 'UTF-8'),
  'encodeURI': (c) => formEncode(c.str(0), c.optStr(1) ?? 'UTF-8'),
};

// ---------------------------------------------------------------- 摘要与加解密

final Map<String, _Api> _cryptoApis = {
  'md5Encode': (c) => hexEncode(digest('MD5', utf8.encode(c.str(0)))),
  'md5Encode16': (c) => hexEncode(digest('MD5', utf8.encode(c.str(0)))).substring(8, 24),
  'digestHex': (c) => hexEncode(digest(c.str(1), utf8.encode(c.str(0)))),
  'digestBase64Str': (c) => base64EncodeStandard(digest(c.str(1), utf8.encode(c.str(0)))),
  'HMacHex': (c) => hexEncode(hmac(c.str(1), utf8.encode(c.str(2)), utf8.encode(c.str(0)))),
  'HMacBase64': (c) => base64EncodeStandard(hmac(c.str(1), utf8.encode(c.str(2)), utf8.encode(c.str(0)))),
  // 密钥为 null 时用随机密钥；IV 不为空时设置
  'createSymmetricCrypto': (c) {
    final key = c[1];
    final crypto = SymmetricCrypto(c.str(0), key == null ? null : c.bytes(1));
    final iv = c[2];
    if (iv != null) {
      final ivBytes = c.bytes(2);
      if (ivBytes.isNotEmpty) crypto.setIv(ivBytes);
    }
    return _Cipher(crypto);
  },
  'cipher.encrypt': (c) => c.cipher().encrypt(_plain(c)),
  'cipher.encryptBase64': (c) => base64EncodeStandard(c.cipher().encrypt(_plain(c))),
  'cipher.encryptHex': (c) => hexEncode(c.cipher().encrypt(_plain(c))),
  'cipher.encryptStr': (c) => utf8.decode(c.cipher().encrypt(_plain(c)), allowMalformed: true),
  'cipher.decrypt': (c) => _decrypt(c),
  'cipher.decryptStr': (c) => utf8.decode(_decrypt(c), allowMalformed: true),
  'cipher.decryptHex': (c) => c.cipher().decrypt(hexDecode(c.str(1))),
  'cipher.decryptBase64': (c) => c.cipher().decrypt(base64DecodeLenient(c.str(1))),
  'cipher.setIv': (c) {
    c.cipher().setIv(c.bytes(1));
    return null;
  },
  for (final MapEntry(:key, :value) in legacyCryptoFunctions.entries)
    key: (c) => value([for (var i = 0; i < c.length; i++) c.str(i)]),
};

/// 加密的明文：字节数组，或文本（可以指定字符集，默认 UTF-8）。
Uint8List _plain(_Call c) {
  final data = c[1];
  if (data is String) return stringToBytes(data, c.optStr(2) ?? 'UTF-8');
  return c.bytes(1);
}

/// `decrypt(文本)` 自动识别十六进制和 Base64，`decrypt(字节数组)` 直接解密。
Uint8List _decrypt(_Call c) {
  final data = c[1];
  return data is String ? c.cipher().decryptText(data) : c.cipher().decrypt(c.bytes(1));
}

// ---------------------------------------------------------------- 时间与文本

final Map<String, _Api> _textApis = {
  'timeFormat': (c) => timeFormat(c.integer(0)),
  'timeFormatUTC': (c) => timeFormatUtc(c.integer(0), c.str(1), c.integer(2)),
  'toNumChapter': (c) {
    final text = c.optStr(0);
    return text == null ? null : toNumChapter(text);
  },
  'htmlFormat': (c) => formatKeepImg(c.str(0), null),
  'randomUUID': (c) => randomUuid(),
  'getWebViewUA': (c) => webViewUserAgent,
  'androidId': (c) => _androidId(c.task),
};

/// 设备编号在书源级存储里的键：不属于任何书源，和书源变量的 `v_` 前缀分开。
const String _androidIdKey = 'app.androidId';

/// `androidId()`：MD3 返回设备的 ANDROID_ID。第一次调用时随机生成并保存，之后一直返回它（fix-explore-compat 设计 D3）。
String _androidId(SourceTask task) {
  final saved = task.storeGet(_androidIdKey);
  if (saved != null) return saved;
  final id = randomAndroidId();
  task.storePut(_androidIdKey, id);
  return id;
}

// ---------------------------------------------------------------- 日志

final Map<String, _Api> _logApis = {
  // 写入书源调试日志，原样返回参数
  'log': (c) {
    final value = c[0];
    c.task.log(value == null ? 'null' : _text(value));
    return value;
  },
  'logType': (c) {
    c.task.log(_typeName(c[0]));
    return null;
  },
  // 没有界面，提示降级为日志
  'toast': (c) {
    c.task.log(c[0] == null ? 'null' : _text(c[0]!));
    return null;
  },
  'longToast': (c) {
    c.task.log(c[0] == null ? 'null' : _text(c[0]!));
    return null;
  },
};

/// `java.logType` 输出的类型名，照 Rhino 里对应的 Java 类。
String _typeName(Object? value) => switch (value) {
  null => 'null',
  String() => 'java.lang.String',
  bool() => 'java.lang.Boolean',
  int() || JsNumber() => 'java.lang.Double',
  JsArray() => 'org.mozilla.javascript.NativeArray',
  JsObject() => 'org.mozilla.javascript.NativeObject',
  ElementList() => 'org.jsoup.select.Elements',
  Node() => 'org.jsoup.nodes.Element',
  _ => value.runtimeType.toString(),
};

// ---------------------------------------------------------------- Cookie

final Map<String, _Api> _cookieApis = {
  'cookie.getCookie': (c) => _cookie(c, c.str(0)),
  'cookie.getKey': (c) => cookieToMap(_cookie(c, c.str(0)))[c.str(1)] ?? '',
  'cookie.setCookie': (c) => c.env.store(StoreRequest(StoreOp.setCookie, c.str(0), value: c.optStr(1) ?? '')),
  'cookie.replaceCookie': (c) => c.env.store(StoreRequest(StoreOp.replaceCookie, c.str(0), value: c.optStr(1) ?? '')),
  'cookie.removeCookie': (c) => c.env.store(StoreRequest(StoreOp.removeCookie, c.str(0))),
  'cookie.cookieToMap': (c) => cookieToMap(c.str(0)),
  'cookie.mapToCookie': (c) {
    final map = c[0];
    if (map is! Map) return null;
    return mapToCookie({for (final MapEntry(:key, :value) in map.entries) '$key': _text(value ?? 'null')});
  },
  // java.getCookie(地址[, 名])
  'getCookie': (c) {
    final cookie = _cookie(c, c.str(0));
    final key = c.optStr(1);
    return key == null ? cookie : (cookieToMap(cookie)[key] ?? '');
  },
};

String _cookie(_Call c, String url) => c.env.store(StoreRequest(StoreOp.getCookie, url)) as String? ?? '';

// ---------------------------------------------------------------- 缓存

final Map<String, _Api> _cacheApis = {
  'cache.put': _cachePut,
  'cache.putFile': _cachePut,
  'cache.get': (c) => c.task.storeGet(c.str(0)),
  'cache.getFile': (c) => c.task.storeGet(c.str(0)),
  'cache.delete': (c) {
    c.task.storeDelete(c.str(0));
    c.env.store(StoreRequest(StoreOp.deleteMemory, c.str(0)));
    return null;
  },
  'cache.putMemory': (c) => c.env.store(StoreRequest(StoreOp.putMemory, c.str(0), value: c.js.resultToJs(c[1]))),
  'cache.getFromMemory': (c) => c.js.argFromJs(c.env.store(StoreRequest(StoreOp.getMemory, c.str(0)))),
  'cache.deleteMemory': (c) => c.env.store(StoreRequest(StoreOp.deleteMemory, c.str(0))),
};

/// `cache.put(键, 值[, 保存秒数])`：值按 JS 的 `String()` 存成文本，秒数为 0 时不过期。
Object? _cachePut(_Call c) {
  final value = c[1];
  c.task.storePut(c.str(0), value == null ? 'null' : _text(value), saveSeconds: c.integer(2));
  return null;
}

// ---------------------------------------------------------------- 书源

final Map<String, _Api> _sourceApis = {
  'source.fields': (c) => SourceJs.sourceFields(c.task.source),
  'source.getKey': (c) => c.task.sourceKey,
  'source.getTag': (c) => c.task.source.bookSourceName,
  'source.getVariable': (c) => c.task.storeGet(c.task.sourceVariableKey) ?? '',
  'source.setVariable': _setSourceVariable,
  'source.putVariable': _setSourceVariable,
  'source.getLoginHeader': (c) => c.task.loginHeader,
  'source.getLoginHeaderMap': (c) => c.task.loginHeaderMap,
  'source.putLoginHeader': (c) {
    c.task.putLoginHeader(c.str(0));
    return null;
  },
  'source.removeLoginHeader': (c) {
    c.task.removeLoginHeader();
    return null;
  },
  'source.getLoginInfo': (c) => c.task.storeGet(c.task.loginInfoKey),
  'source.getLoginInfoMap': (c) => _loginInfoMap(c.task),
  'source.putLoginInfo': (c) {
    c.task.storePut(c.task.loginInfoKey, c.str(0));
    return true;
  },
  'source.removeLoginInfo': (c) {
    c.task.storeDelete(c.task.loginInfoKey);
    return null;
  },
};

/// 书源自定义变量：null 为删除。
Object? _setSourceVariable(_Call c) {
  final value = c.optStr(0);
  if (value == null) {
    c.task.storeDelete(c.task.sourceVariableKey);
  } else {
    c.task.storePut(c.task.sourceVariableKey, value);
  }
  return null;
}

/// 已保存的登录信息按 JSON 解析（失败为空）；没有时，`loginUi` 是 JSON 数组的话取其中非按钮项的 `name` 到 `default`
/// （缺省为空串），保存为登录信息后返回。`loginUi` 是 JS 时（需要执行登录脚本）返回空。
Map<String, String> _loginInfoMap(SourceTask task) {
  final info = task.storeGet(task.loginInfoKey);
  if (info != null) {
    try {
      return parseLenientStringMap(info);
    } on FormatException {
      return {};
    }
  }
  final loginUi = task.source.loginUi;
  if (loginUi == null || loginUi.trim().isEmpty || loginUi.startsWith('@js:') || loginUi.startsWith('<js>')) return {};
  Object? rows;
  try {
    rows = parseLenientJson(loginUi);
  } on FormatException {
    return {};
  }
  if (rows is! List) return {};
  final map = <String, String>{
    for (final row in rows)
      if (row is Map && row['type'] != 'button' && row['name'] != null) '${row['name']}': '${row['default'] ?? ''}',
  };
  if (map.isNotEmpty) task.storePut(task.loginInfoKey, jsonEncode(map));
  return map;
}

// ---------------------------------------------------------------- 书籍和章节

final Map<String, _Api> _bookApis = {
  'book.set': (c) {
    final book = c.frame.book;
    if (book != null) _setBookField(book, c.str(0), c[1]);
    return null;
  },
  'book.getVariable': (c) => c.frame.book?.variables[c.str(0)] ?? '',
  'book.putVariable': (c) => _putVariable(c.frame.book?.variables, c.str(0), c.optStr(1)),
  'book.getCustomVariable': (c) => c.frame.book?.variables['custom'] ?? '',
  'book.putCustomVariable': (c) => _putVariable(c.frame.book?.variables, 'custom', c.optStr(0)),
  'book.setReverseToc': (c) {
    final book = c.frame.book;
    if (book is Book) book.reverseToc = c[0] == true;
    return null;
  },
  'book.upCustomIntro': (c) {
    final book = c.frame.book;
    if (book is Book) book.customIntro = book.intro;
    return null;
  },
  'chapter.getVariable': (c) => c.frame.chapter?.variables[c.str(0)] ?? '',
  'chapter.putVariable': (c) => _putVariable(c.frame.chapter?.variables, c.str(0), c.optStr(1)),
};

/// 变量的值为 null 时删除。
bool _putVariable(Map<String, String>? variables, String key, String? value) {
  if (variables == null) return false;
  if (value == null) {
    variables.remove(key);
  } else {
    variables[key] = value;
  }
  return true;
}

/// JS 给 `book` 的属性赋值，写回书籍（只认书籍上有的字段）。
void _setBookField(Object book, String key, Object? value) {
  final text = value == null ? null : _text(value);
  switch (book) {
    case Book():
      switch (key) {
        case 'name':
          book.name = text ?? '';
        case 'author':
          book.author = text ?? '';
        case 'bookUrl':
          book.bookUrl = text ?? '';
        case 'tocUrl':
          book.tocUrl = text ?? '';
        case 'kind':
          book.kind = text;
        case 'coverUrl':
          book.coverUrl = text;
        case 'intro':
          book.intro = text;
        case 'customIntro':
          book.customIntro = text;
        case 'wordCount':
          book.wordCount = text;
        case 'latestChapterTitle':
          book.latestChapterTitle = text;
      }
    case SearchBook():
      switch (key) {
        case 'name':
          book.name = text ?? '';
        case 'author':
          book.author = text ?? '';
        case 'bookUrl':
          book.bookUrl = text ?? '';
        case 'kind':
          book.kind = text;
        case 'coverUrl':
          book.coverUrl = text;
        case 'intro':
          book.intro = text;
        case 'wordCount':
          book.wordCount = text;
        case 'latestChapterTitle':
          book.latestChapterTitle = text;
      }
  }
}
