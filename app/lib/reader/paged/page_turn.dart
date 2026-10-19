import '../reader_settings.dart';

/// 松手时按速度判定的阈值，逻辑像素每秒（设计 D11）。
const flingVelocity = 300.0;

/// 速度不够时，拖过页宽的这个比例就完成翻页（设计 D11）。
const completeFraction = 0.35;

/// 松手判定（设计 D11）：速度优先，距离兜底。
///
/// [velocity] 是松手时的水平速度（向右为正），[t] 是已经拖过的比例，[forward] 是往后翻（手指向左）。
/// 速度的绝对值不小于 [flingVelocity] 时看方向：和翻页方向相同就完成，相反就回到原页；否则 t ≥ [completeFraction] 完成。
bool shouldComplete({required double velocity, required double t, required bool forward}) {
  if (velocity.abs() >= flingVelocity) return forward ? velocity < 0 : velocity > 0;
  return t >= completeFraction;
}

/// 翻页过程中两页的位置（设计 D10）：[current] 是当前页，[other] 是要翻到的页，都是横坐标；
/// [otherOnTop] 为真时 [other] 盖在 [current] 上面。
typedef PagePlacement = ({double current, double other, bool otherOnTop});

/// 翻页进度为 [t]（0 到 1）时两页的位置，[width] 是页宽：
///
/// ```
/// 往后翻  滑动: 当前页 -t*W,      下一页 (1-t)*W
///         覆盖: 当前页 -t*W 在上, 下一页 0 在下
/// 往前翻  滑动: 上一页 -(1-t)*W,  当前页 t*W
///         覆盖: 上一页 -(1-t)*W 在上, 当前页 0 在下
/// ```
///
/// 无动画不播放过程，[PageMode.none] 按覆盖算，只在 t 为 0 或 1 时用到。
PagePlacement placePages(PageMode mode, {required bool forward, required double t, required double width}) {
  final slide = mode == PageMode.slide;
  if (forward) return (current: -t * width, other: slide ? (1 - t) * width : 0, otherOnTop: false);
  return (current: slide ? t * width : 0, other: -(1 - t) * width, otherOnTop: true);
}
