/// `java.net.URL` 的解析和相对地址拼接，照 OpenJDK 的 `URL(URL, String)` 和 `URLStreamHandler.parseURL` 移植。
///
/// MD3 用它把规则取到的地址转成绝对地址。它和 Dart 的 `Uri.resolve` 不同：不做百分号编码（中文、空格、
/// Legado 的 `,{选项}` 后缀都原样保留），`../` 越过根目录时保留在路径里。
library;

final class JavaUrl {
  JavaUrl._({
    required this.protocol,
    required this.authority,
    required this.userInfo,
    required this.host,
    required this.port,
    required this.path,
    required this.query,
    required this.ref,
  });

  /// `new URL(spec)`，不合法时抛出 [FormatException]。
  factory JavaUrl.parse(String spec) => JavaUrl._resolve(null, spec);

  /// `new URL(context, spec)`，不合法时抛出 [FormatException]。
  factory JavaUrl.resolve(JavaUrl context, String spec) => JavaUrl._resolve(context, spec);

  static JavaUrl? tryParse(String spec) {
    try {
      return JavaUrl.parse(spec);
    } on FormatException {
      return null;
    }
  }

  final String protocol;
  final String? authority;
  final String? userInfo;
  final String host;
  final int port;
  final String path;
  final String? query;
  final String? ref;

  /// 有处理程序的协议（Android 上的 `URL` 只认这些）。
  static const Set<String> _knownProtocols = {'http', 'https', 'ftp', 'file', 'jar'};

  static JavaUrl _resolve(JavaUrl? context, String spec) {
    var start = 0;
    var limit = spec.length;
    while (limit > 0 && spec.codeUnitAt(limit - 1) <= 0x20) {
      limit--;
    }
    while (start < limit && spec.codeUnitAt(start) <= 0x20) {
      start++;
    }
    if (_regionMatchesIgnoreCase(spec, start, 'url:')) start += 4;
    final isRef = start < spec.length && spec[start] == '#';

    String? newProtocol;
    if (!isRef) {
      for (var i = start; i < limit && spec[i] != '/'; i++) {
        if (spec[i] == ':') {
          final candidate = spec.substring(start, i).toLowerCase();
          if (_isValidProtocol(candidate)) {
            newProtocol = candidate;
            start = i + 1;
          }
          break;
        }
      }
    }

    var protocol = newProtocol;
    String? authority;
    String? userInfo;
    String? host;
    var port = -1;
    String? path;
    String? query;
    String? ref;
    var isRelative = false;
    if (context != null && (newProtocol == null || newProtocol == context.protocol)) {
      // 上下文是层级地址时，带同样协议的 spec 按相对地址处理（RFC 2396 5.2.3）
      if (context.path.startsWith('/')) newProtocol = null;
      if (newProtocol == null) {
        protocol = context.protocol;
        authority = context.authority;
        userInfo = context.userInfo;
        host = context.host;
        port = context.port;
        path = context.path;
        isRelative = true;
      }
    }
    if (protocol == null) throw FormatException('no protocol', spec);
    if (!_knownProtocols.contains(protocol)) throw FormatException('unknown protocol: $protocol', spec);

    final hash = spec.indexOf('#', start);
    if (hash >= 0) {
      ref = spec.substring(hash + 1, limit);
      limit = hash;
    }
    if (isRelative && start == limit) {
      query = context!.query;
      ref ??= context.ref;
    }

    return _parseUrl(
      protocol: protocol,
      authority: authority,
      userInfo: userInfo,
      host: host,
      port: port,
      path: path,
      query: query,
      ref: ref,
      spec: spec,
      start: start,
      limit: limit,
    );
  }

  /// `URLStreamHandler.parseURL`。
  static JavaUrl _parseUrl({
    required String protocol,
    required String? authority,
    required String? userInfo,
    required String? host,
    required int port,
    required String? path,
    required String? query,
    required String? ref,
    required String spec,
    required int start,
    required int limit,
  }) {
    var isRelPath = false;
    var queryOnly = false;

    if (start < limit) {
      final queryStart = spec.indexOf('?');
      queryOnly = queryStart == start;
      if (queryStart != -1 && queryStart < limit) {
        query = spec.substring(queryStart + 1, limit);
        if (limit > queryStart) limit = queryStart;
        spec = spec.substring(0, queryStart);
      }
    }

    final isUncName = start <= limit - 4 && spec.startsWith('////', start);
    if (!isUncName && start <= limit - 2 && spec.startsWith('//', start)) {
      start += 2;
      var i = spec.indexOf('/', start);
      if (i < 0 || i > limit) {
        i = spec.indexOf('?', start);
        if (i < 0 || i > limit) i = limit;
      }
      host = authority = spec.substring(start, i);

      final at = authority.indexOf('@');
      if (at != -1) {
        if (at != authority.lastIndexOf('@')) {
          // 多个 @：不解析用户信息和主机
          userInfo = null;
          host = null;
        } else {
          userInfo = authority.substring(0, at);
          host = authority.substring(at + 1);
        }
      } else {
        userInfo = null;
      }
      if (host != null) {
        port = -1;
        if (host.isNotEmpty && host[0] == '[') {
          final close = host.indexOf(']');
          if (close <= 2) throw FormatException('Invalid authority field: $authority', spec);
          final whole = host;
          host = whole.substring(0, close + 1);
          if (whole.length > close + 1) {
            if (whole[close + 1] != ':') throw FormatException('Invalid authority field: $authority', spec);
            if (whole.length > close + 2) port = _parsePort(whole.substring(close + 2), spec);
          }
        } else {
          final colon = host.indexOf(':');
          if (colon >= 0) {
            if (host.length > colon + 1) port = _parsePort(host.substring(colon + 1), spec);
            host = host.substring(0, colon);
          }
        }
      } else {
        host = '';
      }
      start = i;
      // 有授权部分时，路径不再继承上下文
      if (authority.isNotEmpty) path = '';
    }
    host ??= '';

    if (start < limit) {
      if (spec[start] == '/') {
        path = spec.substring(start, limit);
      } else if (path != null && path.isNotEmpty) {
        isRelPath = true;
        final slash = path.lastIndexOf('/');
        final separator = slash == -1 && authority != null ? '/' : '';
        path = path.substring(0, slash + 1) + separator + spec.substring(start, limit);
      } else {
        path = spec.substring(start, limit);
        path = authority != null ? '/$path' : path;
      }
    } else if (queryOnly && path != null) {
      var slash = path.lastIndexOf('/');
      if (slash < 0) slash = 0;
      path = '${path.substring(0, slash)}/';
    }
    path ??= '';

    if (isRelPath) {
      int i;
      while ((i = path!.indexOf('/./')) >= 0) {
        path = path.substring(0, i) + path.substring(i + 2);
      }
      i = 0;
      while ((i = path!.indexOf('/../', i)) >= 0) {
        final previous = i > 0 ? path.lastIndexOf('/', i - 1) : -1;
        if (i > 0 && previous >= 0 && path.indexOf('/../', previous) != 0) {
          path = path.substring(0, previous) + path.substring(i + 3);
          i = 0;
        } else {
          i += 3;
        }
      }
      while (path!.endsWith('/..')) {
        final dots = path.indexOf('/..');
        final previous = dots > 0 ? path.lastIndexOf('/', dots - 1) : -1;
        if (previous < 0) break;
        path = path.substring(0, previous + 1);
      }
      if (path.startsWith('./') && path.length > 2) path = path.substring(2);
      if (path.endsWith('/.')) path = path.substring(0, path.length - 1);
    }

    return JavaUrl._(
      protocol: protocol,
      authority: authority,
      userInfo: userInfo,
      host: host,
      port: port,
      path: path,
      query: query,
      ref: ref,
    );
  }

  /// `URL.toExternalForm()`。
  @override
  String toString() {
    final out = StringBuffer('$protocol:');
    if (authority case final authority? when authority.isNotEmpty) out.write('//$authority');
    out.write(path);
    if (query != null) out.write('?$query');
    if (ref != null) out.write('#$ref');
    return out.toString();
  }

  static int _parsePort(String text, String spec) {
    if (text.isEmpty || !text.codeUnits.every((c) => c >= 0x30 && c <= 0x39)) {
      throw FormatException('Invalid port', spec);
    }
    return int.parse(text);
  }

  static bool _isValidProtocol(String protocol) {
    if (protocol.isEmpty) return false;
    final first = protocol.codeUnitAt(0);
    if (!_isAsciiLetter(first)) return false;
    return protocol.codeUnits.skip(1).every((c) => _isAsciiLetter(c) || (c >= 0x30 && c <= 0x39) || c == 0x2E || c == 0x2B || c == 0x2D);
  }

  static bool _isAsciiLetter(int c) => (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);

  static bool _regionMatchesIgnoreCase(String text, int start, String other) =>
      text.length - start >= other.length && text.substring(start, start + other.length).toLowerCase() == other;
}

final RegExp _dataUrl = RegExp(r'^data:.*?;base64,(.*)$');

/// MD3 的 `String.isDataUrl()`：整串匹配 `data:...;base64,...`（`.` 不匹配换行）。
bool isDataUrl(String text) => _dataUrl.hasMatch(text);

/// MD3 的 `String.isAbsUrl()`。
bool isAbsUrl(String text) {
  final lower = text.toLowerCase();
  return lower.startsWith('http://') || lower.startsWith('https://');
}

/// MD3 的 `NetworkUtils.getAbsoluteURL(URL?, String)`：
/// http(s) 和 data 地址原样返回，`javascript` 开头的返回空串，其余按 [base] 拼接，拼接失败时返回去掉首尾空白的原文。
String absoluteUrl(JavaUrl? base, String relative) {
  final trimmed = relative.trim();
  if (base == null) return trimmed;
  if (isAbsUrl(trimmed) || isDataUrl(trimmed)) return trimmed;
  if (trimmed.startsWith('javascript')) return '';
  try {
    return JavaUrl.resolve(base, relative).toString();
  } on FormatException {
    return trimmed;
  }
}

/// MD3 的 `NetworkUtils.getAbsoluteURL(String?, String)`：基准地址从第一个逗号处截断（去掉 `,{选项}`）。
String absoluteUrlFrom(String? base, String relative) {
  if (base == null || base.isEmpty) return relative.trim();
  final comma = base.indexOf(',');
  return absoluteUrl(JavaUrl.tryParse(comma < 0 ? base : base.substring(0, comma)), relative);
}
