import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:rule_engine/rule_engine.dart';

import '../ui/tokens.dart';
import 'explore_books_page.dart';
import 'source_repository.dart';

/// 分类排版的尺寸，和 Legado 3.25 的发现页相同（add-explore 设计 D4）：FlexboxLayout 的内边距、
/// 分类 TextView 的外边距和左右内边距、`shape_space_divider` 的大小。
abstract final class ExploreKindMetrics {
  static const padding = 3.0;
  static const margin = 3.0;
  static const divider = 8.0;
  static const textPadding = 12.0;
}

/// 排版的输入：分类的样式和内容宽度（文字宽度加左右内边距）。
typedef FlexItem = ({FlexStyle style, double contentWidth});

/// 排版的结果：分类的下标和宽度（不含外边距）。
typedef FlexCell = ({int index, double width});

/// 照 FlexboxLayout（横向、换行）把分类排成多行（explore「分类排版」）。[width] 是去掉容器内边距后的可用宽度。
List<List<FlexCell>> flexRows(List<FlexItem> items, double width) {
  const outerMargin = 2 * ExploreKindMetrics.margin;
  final rows = <List<FlexCell>>[];
  var row = <({int index, double base, FlexStyle style})>[];
  var used = 0.0;

  void finishRow() {
    if (row.isEmpty) return;
    final free = width - used;
    final grow = row.fold(0.0, (sum, item) => sum + item.style.grow);
    final shrink = row.fold(0.0, (sum, item) => sum + item.style.shrink * item.base);
    rows.add([
      for (final item in row)
        (
          index: item.index,
          width: switch (free) {
            > 0 when grow > 0 => item.base + free * item.style.grow / grow,
            < 0 when shrink > 0 => math.max(0, item.base + free * item.style.shrink * item.base / shrink),
            _ => item.base,
          },
        ),
    ]);
    row = [];
    used = 0;
  }

  for (final (index, item) in items.indexed) {
    final style = item.style;
    final base = style.basisPercent >= 0 ? width * style.basisPercent : item.contentWidth;
    // 浮点误差：几个比例加起来正好铺满时不该换行
    if (row.isNotEmpty && (style.wrapBefore || used + ExploreKindMetrics.divider + base + outerMargin > width + 0.01)) finishRow();
    used += (row.isEmpty ? 0 : ExploreKindMetrics.divider) + base + outerMargin;
    row.add((index: index, base: base, style: style));
  }
  finishRow();
  return rows;
}

/// 一个书源的分类（explore「分类排版」）：有地址的普通分类可以点，没有地址的是小标题，交互式分类灰色不能点。
class ExploreKindsView extends StatelessWidget {
  const ExploreKindsView({super.key, required this.entry, required this.kinds});

  final SourceEntry entry;
  final List<ExploreKind> kinds;

  static const _textStyle = TextStyle(fontSize: 14, height: 1.3);
  static const _headerStyle = TextStyle(fontSize: 14, height: 1.3, fontWeight: FontWeight.w600);

  /// 没有地址的普通分类是小标题。
  static bool _isHeader(ExploreKind kind) => kind.type == ExploreKind.urlType && (kind.url?.trim().isEmpty ?? true);

  static TextStyle _styleOf(ExploreKind kind) => _isHeader(kind) ? _headerStyle : _textStyle;

  @override
  Widget build(BuildContext context) {
    // 量宽度要用显示时的完整样式（继承的字距等），否则量出来窄一点，文字就被省略
    final inherited = DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.textScalerOf(context);
    double contentWidth(ExploreKind kind) =>
        _textWidth(kind.title, inherited.merge(_styleOf(kind)), scaler) + 2 * ExploreKindMetrics.textPadding;
    return Padding(
      padding: const EdgeInsets.all(ExploreKindMetrics.padding),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final items = [for (final kind in kinds) (style: kind.style, contentWidth: contentWidth(kind))];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: ExploreKindMetrics.divider,
            children: [
              for (final row in flexRows(items, constraints.maxWidth))
                Row(
                  spacing: ExploreKindMetrics.divider,
                  children: [
                    for (final cell in row)
                      Padding(
                        padding: const EdgeInsets.all(ExploreKindMetrics.margin),
                        child: SizedBox(width: cell.width, child: _kind(context, kinds[cell.index])),
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }

  /// 文字宽度，向上取整到整像素（和 Android 的 wrap_content 一样）。
  static double _textWidth(String text, TextStyle style, TextScaler scaler) {
    final painter = TextPainter(text: TextSpan(text: text, style: style), textScaler: scaler, maxLines: 1, textDirection: TextDirection.ltr)
      ..layout();
    final width = painter.width.ceilToDouble();
    painter.dispose();
    return width;
  }

  Widget _kind(BuildContext context, ExploreKind kind) {
    final colors = AppColors.of(context);
    Widget label(Color color) =>
        Center(child: Text(kind.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: _styleOf(kind).copyWith(color: color)));
    const padding = EdgeInsets.symmetric(horizontal: ExploreKindMetrics.textPadding, vertical: 6);
    // 小标题：不加底色，不能点
    if (_isHeader(kind)) return Padding(padding: padding, child: label(colors.textSecondary));
    final enabled = kind.type == ExploreKind.urlType;
    return Material(
      color: colors.fill,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled
            ? () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ExploreBooksPage(entry: entry, kind: kind)))
            : null,
        child: Padding(padding: padding, child: label(enabled ? colors.textPrimary : colors.textSecondary.withValues(alpha: 0.5))),
      ),
    );
  }
}
