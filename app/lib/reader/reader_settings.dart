import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/providers.dart';

/// 配色来自花火阅读 1.3.3 APK 的 Profile.setReaderStyle；按钮色与正文背景分别定义。
/// 枚举名称用于持久化，保留已有名称。
enum ReaderTheme {
  light('亮', Color(0xFFF8F8FA), Color(0xFF0E0E0E), Color(0xFFFFFFFF)),
  sepia('米黄', Color(0xFFDDD7BE), Color(0xFF0E0E0E), Color(0xFFDDD9C7)),
  green('浅绿', Color(0xFFD3E2C5), Color(0xFF0E0E0E), Color(0xFFDAE3CE)),
  dark('暗', Color(0xFF000000), Color(0xFFB1B1B1), Color(0xFF1A191F));

  const ReaderTheme(this.label, this.background, this.foreground, this.swatch);

  final String label;
  final Color background;
  final Color foreground;
  final Color swatch;
}

/// 翻页方式（reader「翻页方式」，add-paged-reader 设计 D14）。前三种是分页，滚动是整章上下滚动。
enum PageMode {
  cover('覆盖'),
  slide('滑动'),
  none('无动画'),
  scroll('滚动');

  const PageMode(this.label);

  final String label;
}

/// 阅读设置：对所有书生效（reader「阅读设置」）。
final class ReaderSettings {
  const ReaderSettings({
    this.fontSize = 18,
    this.fontId = '',
    this.lineHeight = 1.8,
    this.theme = ReaderTheme.light,
    this.pageMode = PageMode.cover,
    this.followSystemDark = true,
    this.paragraphSpacing = 0.6,
    this.indent = 2,
    this.margin = 20,
    this.keepScreenOn = false,
    this.brightnessFollowSystem = true,
    this.brightness = 0.4,
  });

  factory ReaderSettings.fromMap(Map<String, String> map) => ReaderSettings(
    fontId: map[_fontId] ?? '',
    fontSize: double.tryParse(map[_fontSize] ?? '')?.clamp(minFontSize, maxFontSize) ?? 18,
    lineHeight: double.tryParse(map[_lineHeight] ?? '')?.clamp(minLineHeight, maxLineHeight) ?? 1.8,
    theme: ReaderTheme.values.asNameMap()[map[_theme]] ?? ReaderTheme.light,
    pageMode: PageMode.values.asNameMap()[map[_pageMode]] ?? PageMode.cover,
    followSystemDark: bool.tryParse(map[_followSystemDark] ?? '') ?? true,
    paragraphSpacing: double.tryParse(map[_paragraphSpacing] ?? '')?.clamp(minParagraphSpacing, maxParagraphSpacing) ?? 0.6,
    indent: int.tryParse(map[_indent] ?? '')?.clamp(minIndent, maxIndent) ?? 2,
    margin: double.tryParse(map[_margin] ?? '')?.clamp(minMargin, maxMargin) ?? 20,
    keepScreenOn: bool.tryParse(map[_keepScreenOn] ?? '') ?? false,
    brightnessFollowSystem: bool.tryParse(map[_brightnessFollowSystem] ?? '') ?? true,
    brightness: double.tryParse(map[_brightness] ?? '')?.clamp(minBrightness, maxBrightness) ?? 0.4,
  );

  static const minFontSize = 12.0;
  static const maxFontSize = 40.0;
  static const minLineHeight = 1.0;
  static const maxLineHeight = 3.0;
  static const minParagraphSpacing = 0.0;
  static const maxParagraphSpacing = 2.0;
  static const minIndent = 0;
  static const maxIndent = 4;
  static const minMargin = 8.0;
  static const maxMargin = 48.0;

  /// 页面调暗范围：0 对应 50% 黑色遮罩，1 无遮罩，不改变系统屏幕亮度。
  static const minBrightness = 0.0;
  static const maxBrightness = 1.0;

  /// 排版面板里行距、段距的三个预设：紧凑、适中、宽松（redesign-minimal-ui 设计 D6）。中间那个是默认值。
  /// 落盘时按一位小数格式化，读回来能和预设精确比较；改版前存下的其它值仍在上面的范围内照常生效，只是没有预设被选中。
  static const lineHeightPresets = [1.5, 1.8, 2.2];
  static const paragraphSpacingPresets = [0.3, 0.6, 1.0];

  static const _fontId = 'reader.fontId';
  static const _fontSize = 'reader.fontSize';
  static const _lineHeight = 'reader.lineHeight';
  static const _theme = 'reader.theme';
  static const _pageMode = 'reader.pageMode';
  static const _followSystemDark = 'reader.followSystemDark';
  static const _paragraphSpacing = 'reader.paragraphSpacing';
  static const _indent = 'reader.indent';
  static const _margin = 'reader.margin';
  static const _keepScreenOn = 'reader.keepScreenOn';
  static const _brightnessFollowSystem = 'reader.brightnessFollowSystem';
  static const _brightness = 'reader.brightness';

  /// 空字符串表示系统字体；其余是应用内字体文件的稳定 ID。
  final String fontId;
  final double fontSize;
  final double lineHeight;
  final ReaderTheme theme;
  final PageMode pageMode;

  /// 打开时，系统是深色模式就用暗主题，否则用 [theme]（reader「阅读主题跟随系统」）。
  final bool followSystemDark;

  /// 段距，字号的倍数；首行缩进，字数（complete-reader-settings 设计 D1）。都相对字号，调字号时比例不变。
  final double paragraphSpacing;
  final int indent;

  /// 正文左右两边离屏幕（安全区）的距离，分页和滚动都用。
  final double margin;

  /// 阅读页显示期间屏幕不自动熄灭（reader「屏幕常亮」）。
  final bool keepScreenOn;

  /// 打开时不加遮罩；关闭时按 [brightness] 叠加黑色调暗层（reader「阅读页亮度」）。
  final bool brightnessFollowSystem;
  final double brightness;

  /// 实际显示的主题（设计 D14）。
  ReaderTheme effectiveTheme(Brightness platform) => followSystemDark && platform == Brightness.dark ? ReaderTheme.dark : theme;

  ReaderSettings copyWith({
    String? fontId,
    double? fontSize,
    double? lineHeight,
    ReaderTheme? theme,
    PageMode? pageMode,
    bool? followSystemDark,
    double? paragraphSpacing,
    int? indent,
    double? margin,
    bool? keepScreenOn,
    bool? brightnessFollowSystem,
    double? brightness,
  }) => ReaderSettings(
    fontId: fontId ?? this.fontId,
    fontSize: fontSize ?? this.fontSize,
    lineHeight: lineHeight ?? this.lineHeight,
    theme: theme ?? this.theme,
    pageMode: pageMode ?? this.pageMode,
    followSystemDark: followSystemDark ?? this.followSystemDark,
    paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
    indent: indent ?? this.indent,
    margin: margin ?? this.margin,
    keepScreenOn: keepScreenOn ?? this.keepScreenOn,
    brightnessFollowSystem: brightnessFollowSystem ?? this.brightnessFollowSystem,
    brightness: brightness ?? this.brightness,
  );

  Map<String, String> toMap() => {
    _fontId: fontId,
    _fontSize: '$fontSize',
    _lineHeight: lineHeight.toStringAsFixed(1),
    _theme: theme.name,
    _pageMode: pageMode.name,
    _followSystemDark: '$followSystemDark',
    _paragraphSpacing: paragraphSpacing.toStringAsFixed(1),
    _indent: '$indent',
    _margin: '$margin',
    _keepScreenOn: '$keepScreenOn',
    _brightnessFollowSystem: '$brightnessFollowSystem',
    _brightness: '$brightness',
  };
}

/// 启动时从数据库读出的设置，在 main 里覆盖。
final initialSettingsProvider = Provider<Map<String, String>>((ref) => const {});

final class ReaderSettingsNotifier extends Notifier<ReaderSettings> {
  @override
  ReaderSettings build() => ReaderSettings.fromMap(ref.read(initialSettingsProvider));

  /// 文件删除完成后按当前选择回落；不依赖字体页是否仍然显示，也不覆盖期间更改的其他设置。
  void resetFontIfSelected(String id) {
    if (state.fontId == id) update(state.copyWith(fontId: ''));
  }

  /// 立即生效并落盘。
  void update(ReaderSettings settings) {
    state = settings;
    final db = ref.read(databaseProvider);
    for (final MapEntry(:key, :value) in settings.toMap().entries) {
      db.putSetting(key, value);
    }
  }
}

final readerSettingsProvider = NotifierProvider<ReaderSettingsNotifier, ReaderSettings>(ReaderSettingsNotifier.new);
