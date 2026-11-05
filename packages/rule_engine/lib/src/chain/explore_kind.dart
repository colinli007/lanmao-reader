import '../text/lenient_json.dart';

/// 发现分类在 FlexboxLayout 里的样式（MD3 的 `FlexChildStyle`），缺少的项取 FlexboxLayout 的默认值。
final class FlexStyle {
  const FlexStyle({this.grow = 0, this.shrink = 1, this.basisPercent = -1, this.wrapBefore = false});

  /// 一行有剩余宽度时分到的比例。
  final double grow;

  /// 一行超出时压缩的比例（乘以基础宽度）。
  final double shrink;

  /// 基础宽度占可用宽度的比例，小于 0 时按内容宽度。
  final double basisPercent;

  /// 从新的一行开始。
  final bool wrapBefore;

  static FlexStyle fromJson(Object? json) {
    if (json is! Map<String, Object?>) return const FlexStyle();
    double number(String key, double fallback) => switch (json[key]) {
      final num value => value.toDouble(),
      final String value => double.tryParse(value.trim()) ?? fallback,
      _ => fallback,
    };
    final wrap = json['layout_wrapBefore'];
    return FlexStyle(
      grow: number('layout_flexGrow', 0),
      shrink: number('layout_flexShrink', 1),
      basisPercent: number('layout_flexBasisPercent', -1),
      wrapBefore: wrap == true || (wrap is String && wrap.trim().toLowerCase() == 'true'),
    );
  }
}

/// 一个发现分类（MD3 的 `ExploreKind`）。普通的 Dart 对象，可以在 isolate 之间传递。
final class ExploreKind {
  const ExploreKind(this.title, {this.url, this.type = urlType, this.style = const FlexStyle()});

  /// 普通分类的类型：点了按 [url] 浏览书籍。MD3 另有 `text`、`button`、`toggle`、`select` 四种交互式分类。
  static const urlType = 'url';

  final String title;

  /// 分类地址，可以带 `{{page}}`；为空的普通分类是小标题。
  final String? url;
  final String type;
  final FlexStyle style;

  @override
  String toString() => 'ExploreKind($title, $url)';
}

/// 按 MD3 的 `BookSource.exploreKinds` 解析发现地址（JS 已经执行过）：去掉首尾空白后是 JSON 数组时按分类对象解析，
/// 不合法时抛出 [FormatException]；否则按 `&&` 和换行拆成多段，每段是 `标题::地址`。
List<ExploreKind> parseExploreKinds(String text) {
  final trimmed = text.trim();
  if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
    final list = parseLenientJson(trimmed) as List<Object?>;
    return [
      for (final item in list)
        if (item is Map<String, Object?>)
          ExploreKind(
            _text(item['title']) ?? '',
            url: _text(item['url']),
            type: _text(item['type']) ?? ExploreKind.urlType,
            style: FlexStyle.fromJson(item['style']),
          ),
    ];
  }
  return [for (final part in trimmed.split(_separator)) _textKind(part)];
}

ExploreKind _textKind(String part) {
  final fields = part.split('::');
  return ExploreKind(fields.first, url: fields.length > 1 ? fields[1] : null);
}

final RegExp _separator = RegExp(r'(&&|\n)+');

String? _text(Object? value) => value == null ? null : jsonText(value);
