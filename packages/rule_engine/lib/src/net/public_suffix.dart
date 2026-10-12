import 'public_suffix_list.dart';

/// 按 publicsuffix.org 的算法匹配公共后缀：例外规则优先，其余取标签最多的规则，都不匹配时按 `*` 处理。
final class PublicSuffixList {
  PublicSuffixList._(this._rules, this._wildcards, this._exceptions);

  factory PublicSuffixList._parse(String source) {
    final rules = <String>{};
    final wildcards = <String>{};
    final exceptions = <String>{};
    for (final rule in source.split('\n')) {
      if (rule.isEmpty) continue;
      if (rule.startsWith('!')) {
        exceptions.add(rule.substring(1));
      } else if (rule.startsWith('*.')) {
        wildcards.add(rule.substring(2));
      } else {
        rules.add(rule);
      }
    }
    return PublicSuffixList._(rules, wildcards, exceptions);
  }

  static final PublicSuffixList instance = PublicSuffixList._parse(publicSuffixRules);

  final Set<String> _rules;

  /// `*.ck` 存为 `ck`。
  final Set<String> _wildcards;

  /// `!www.ck` 存为 `www.ck`。
  final Set<String> _exceptions;

  /// 公共后缀加一级，即注册域名。[host] 本身就是公共后缀时返回 null。
  String? effectiveTldPlusOne(String host) {
    final labels = host.toLowerCase().split('.');
    if (labels.any((label) => label.isEmpty)) return null;
    final suffixLength = _suffixLength(labels);
    if (labels.length <= suffixLength) return null;
    return labels.sublist(labels.length - suffixLength - 1).join('.');
  }

  /// 公共后缀占几个标签。
  int _suffixLength(List<String> labels) {
    var longest = 1;
    for (var i = 0; i < labels.length; i++) {
      final domain = labels.sublist(i).join('.');
      final length = labels.length - i;
      // 例外规则的公共后缀是去掉最左一级之后的部分
      if (_exceptions.contains(domain)) return length - 1;
      if (length > longest && _rules.contains(domain)) longest = length;
      if (i > 0 && length + 1 > longest && _wildcards.contains(domain)) longest = length + 1;
    }
    return longest;
  }
}

/// Cookie 分组用的域名，照 MD3 的 `NetworkUtils.getSubDomain`：
/// http(s) 地址取主机的注册域名，IP 地址原样返回，主机本身是公共后缀时返回主机；
/// 不是 http(s) 地址时原样返回，解析失败时返回协议加主机部分。
String cookieDomain(String url) {
  final baseUrl = _baseUrl(url);
  if (baseUrl == null) return url;
  final host = Uri.tryParse(baseUrl)?.host;
  if (host == null || host.isEmpty) return baseUrl;
  if (_isIpAddress(host)) return host;
  return PublicSuffixList.instance.effectiveTldPlusOne(host) ?? host;
}

String? _baseUrl(String url) {
  final lower = url.toLowerCase();
  if (!lower.startsWith('http://') && !lower.startsWith('https://')) return null;
  final index = url.indexOf('/', 9);
  return index == -1 ? url : url.substring(0, index);
}

final RegExp _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');

// Uri 解析出的 IPv6 主机不带方括号，含冒号
bool _isIpAddress(String host) => host.contains(':') || _ipv4.hasMatch(host);
