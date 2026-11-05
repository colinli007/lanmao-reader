import 'package:flutter_test/flutter_test.dart';
import 'package:lanmao_reader/online/explore_kinds.dart';
import 'package:rule_engine/rule_engine.dart';

// explore「分类排版」：和 Legado 的 FlexboxLayout 相同的尺寸
void main() {
  FlexItem item({double basis = -1, double grow = 0, double shrink = 1, bool wrap = false, double content = 50}) =>
      (style: FlexStyle(basisPercent: basis, grow: grow, shrink: shrink, wrapBefore: wrap), contentWidth: content);

  /// 一行占的宽度：分类宽度、外边距、分隔。
  double used(List<FlexCell> row) =>
      row.fold(0.0, (sum, cell) => sum + cell.width + 2 * ExploreKindMetrics.margin) + ExploreKindMetrics.divider * (row.length - 1);

  test('0.25、伸展 1：338dp 宽时一行排 3 个，每行铺满', () {
    final rows = flexRows([for (var i = 0; i < 5; i++) item(basis: 0.25, grow: 1)], 338);
    expect(rows.map((row) => row.map((cell) => cell.index)), [
      [0, 1, 2],
      [3, 4],
    ]);
    for (final row in rows) {
      expect(used(row), closeTo(338, 1e-9));
    }
    // 第二行 2 个平分剩余宽度
    expect(rows[1][0].width, closeTo(rows[1][1].width, 1e-9));
  });

  test('0.2：一行排 4 个', () {
    expect(flexRows([for (var i = 0; i < 8; i++) item(basis: 0.2, grow: 1)], 338).map((row) => row.length), [4, 4]);
  });

  test('比例正好铺满时不换行', () {
    // 两个 0.5：338 * 0.5 * 2 + 外边距 12 + 分隔 8 > 338，换行；减去外边距和分隔后的比例正好铺满
    final basis = (338 - 2 * 2 * ExploreKindMetrics.margin - ExploreKindMetrics.divider) / 2 / 338;
    expect(flexRows([item(basis: basis), item(basis: basis)], 338).single, hasLength(2));
  });

  test('强制换行和整行的小标题', () {
    final rows = flexRows([item(basis: 1, grow: 1), item(basis: 0.25), item(basis: 0.25, wrap: true), item(basis: 0.25)], 338);
    expect(rows.map((row) => row.map((cell) => cell.index)), [
      [0],
      [1],
      [2, 3],
    ]);
    // 伸展为 0 时不补满
    expect(rows[1].single.width, 338 * 0.25);
  });

  test('没有比例时按内容宽度，伸展按比例分剩余宽度', () {
    final rows = flexRows([item(content: 60, grow: 1), item(content: 60, grow: 3)], 200);
    final free = 200 - (60 + 60 + 4 * ExploreKindMetrics.margin + ExploreKindMetrics.divider);
    expect(rows.single[0].width, closeTo(60 + free / 4, 1e-9));
    expect(rows.single[1].width, closeTo(60 + free * 3 / 4, 1e-9));
  });

  test('单个分类比可用宽度还宽时压缩到一行', () {
    final rows = flexRows([item(content: 500), item(content: 40)], 200);
    expect(rows, hasLength(2));
    expect(rows[0].single.width, 200 - 2 * ExploreKindMetrics.margin);
  });
}
