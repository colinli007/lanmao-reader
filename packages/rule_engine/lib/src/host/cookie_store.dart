import '../net/public_suffix.dart';

/// MD3 的 `CookieStore` + `CookieManager`：按注册域名分组，只保存名和值。
///
/// 只存在主 isolate 的内存里，所有 worker 的请求共用。持久 Cookie（带 Expires 或 Max-Age）和会话 Cookie 分开存，
/// 读取时合并，同名时会话 Cookie 优先；过期时间、路径都不看。值为空白的 Cookie 被丢弃，所以「删除 Cookie」不会生效。
final class CookieStore {
  final Map<String, String> _persistent = {};
  final Map<String, String> _session = {};

  /// [url] 所属注册域名的 Cookie，形如 `a=1; b=2`，没有时为空串。
  String getCookie(String url) {
    final domain = cookieDomain(url);
    final merged = mergeCookies([_persistent[domain] ?? '', _session[domain]]);
    return merged ?? '';
  }

  /// 保存响应的 `Set-Cookie`（MD3 的 `CookieManager.saveResponse`）。[url] 是这一跳实际请求的地址。
  void saveResponse(Uri url, List<String> setCookies) {
    final domain = cookieDomain(url.toString());
    final cookies = [for (final header in setCookies) ?_parseSetCookie(url.host, header)];
    _updateSession(domain, _cookieString(cookies.where((cookie) => !cookie.persistent)));
    _replacePersistent(domain, _cookieString(cookies.where((cookie) => cookie.persistent)));
  }

  /// 直接写入（测试和以后的登录、JS 的 `cookie.setCookie` 用），覆盖原有的持久 Cookie。
  void setCookie(String url, String cookie) => _persistent[cookieDomain(url)] = cookie;

  void _updateSession(String domain, String cookies) {
    final existing = _session[domain];
    if (existing == null || existing.isEmpty) {
      _session[domain] = cookies;
      return;
    }
    final merged = mergeCookies([existing, cookies]);
    if (merged != null) _session[domain] = merged;
  }

  void _replacePersistent(String domain, String cookies) {
    if (cookies.isEmpty) return;
    final existing = _persistent[domain] ?? '';
    if (existing.isEmpty) {
      _persistent[domain] = cookies;
      return;
    }
    final map = cookieToMap(existing)..addAll(cookieToMap(cookies));
    _persistent[domain] = mapToCookie(map) ?? '';
  }

  static String _cookieString(Iterable<_Cookie> cookies) => cookies.map((c) => '${c.name}=${c.value}').join('; ');
}

/// MD3 的 `CookieStore.cookieToMap`：按 `;` 和第一个 `=` 切分，值为空白（字面量 null 除外）的丢弃。
Map<String, String> cookieToMap(String cookie) {
  final map = <String, String>{};
  if (cookie.trim().isEmpty) return map;
  for (final pair in cookie.split(';')) {
    final eq = pair.indexOf('=');
    if (eq < 0 || eq == pair.length - 1) continue;
    final key = _trimJava(pair.substring(0, eq));
    final value = pair.substring(eq + 1);
    if (value.trim().isNotEmpty || _trimJava(value) == 'null') map[key] = _trimJava(value);
  }
  return map;
}

String? mapToCookie(Map<String, String> map) =>
    map.isEmpty ? null : map.entries.map((entry) => '${entry.key}=${entry.value}').join('; ');

/// 依次合并，后面的同名值覆盖前面的；结果为空时为 null。
String? mergeCookies(List<String?> cookies) {
  final map = <String, String>{};
  for (final cookie in cookies) {
    if (cookie != null) map.addAll(cookieToMap(cookie));
  }
  return mapToCookie(map);
}

final class _Cookie {
  const _Cookie(this.name, this.value, {required this.persistent});

  final String name;
  final String value;
  final bool persistent;
}

/// OkHttp 的 `Cookie.parse`：名字不能为空，名字和值不能含控制字符或非 ASCII 字符；
/// Domain 属性必须和主机匹配，且不能是公共后缀；有合法的 Expires 或 Max-Age 时是持久 Cookie。
_Cookie? _parseSetCookie(String host, String header) {
  final parts = header.split(';');
  final pair = parts.first;
  final eq = pair.indexOf('=');
  if (eq < 0) return null;
  final name = _trimJava(pair.substring(0, eq));
  final value = _trimJava(pair.substring(eq + 1));
  if (name.isEmpty || _hasControlOrNonAscii(name) || _hasControlOrNonAscii(value)) return null;

  var persistent = false;
  String? domain;
  for (final attribute in parts.skip(1)) {
    final attrEq = attribute.indexOf('=');
    final attrName = _trimJava(attrEq < 0 ? attribute : attribute.substring(0, attrEq)).toLowerCase();
    final attrValue = attrEq < 0 ? '' : _trimJava(attribute.substring(attrEq + 1));
    switch (attrName) {
      case 'expires':
        if (_isCookieDate(attrValue)) persistent = true;
      case 'max-age':
        if (RegExp(r'^-?\d+$').hasMatch(attrValue)) persistent = true;
      case 'domain':
        var candidate = attrValue.startsWith('.') ? attrValue.substring(1) : attrValue;
        candidate = candidate.toLowerCase();
        if (candidate.isNotEmpty && !candidate.endsWith('.')) domain = candidate;
    }
  }
  final urlHost = host.toLowerCase();
  if (domain == null) {
    domain = urlHost;
  } else if (!_domainMatch(urlHost, domain)) {
    return null;
  }
  if (urlHost.length != domain.length && PublicSuffixList.instance.effectiveTldPlusOne(domain) == null) return null;
  return _Cookie(name, value, persistent: persistent);
}

bool _domainMatch(String urlHost, String domain) {
  if (urlHost == domain) return true;
  return urlHost.endsWith(domain) &&
      urlHost[urlHost.length - domain.length - 1] == '.' &&
      !RegExp(r'^[\d.]+$').hasMatch(urlHost) &&
      !urlHost.contains(':');
}

bool _hasControlOrNonAscii(String text) => text.codeUnits.any((c) => c <= 0x1F || c >= 0x7F);

/// RFC 6265 的 cookie-date：要找到时间、日、月、年四个部分。
bool _isCookieDate(String text) {
  final tokens = text.split(RegExp(r'[\x09\x20-\x2F\x3B-\x40\x5B-\x60\x7B-\x7E]+')).where((t) => t.isNotEmpty);
  var time = false;
  var day = false;
  var month = false;
  var year = false;
  for (final token in tokens) {
    if (!time && RegExp(r'^\d{1,2}:\d{1,2}:\d{1,2}').hasMatch(token)) {
      time = true;
    } else if (!day && RegExp(r'^\d{1,2}(\D|$)').hasMatch(token)) {
      day = true;
    } else if (!month && _months.contains(token.length >= 3 ? token.substring(0, 3).toLowerCase() : '')) {
      month = true;
    } else if (!year && RegExp(r'^\d{2,4}(\D|$)').hasMatch(token)) {
      year = true;
    }
  }
  return time && day && month && year;
}

const Set<String> _months = {'jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'};

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
