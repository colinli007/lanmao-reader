import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/providers.dart';

/// 阅读主题（设计 D9）。
enum ReaderTheme {
  light('亮', Color(0xFFFFFFFF), Color(0xFF1F1F1F)),
  dark('暗', Color(0xFF121212), Color(0xFFB8B8B8)),
  sepia('护眼', Color(0xFFF2E8CF), Color(0xFF3B3326));

  const ReaderTheme(this.label, this.background, this.foreground);

  final String label;
  final Color background;
  final Color foreground;
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

  /// 阅读页亮度的范围：下限不是 0，部分 Android 机型上 0 几乎全黑（add-reader-brightness 设计 D3）。
  static const minBrightness = 0.01;
  static const maxBrightness = 1.0;

  /// 排版面板里行距、段距的三个预设：紧凑、适中、宽松（redesign-minimal-ui 设计 D6）。中间那个是默认值。
  /// 落盘时按一位小数格式化，读回来能和预设精确比较；改版前存下的其它值仍在上面的范围内照常生效，只是没有预设被选中。
  static const lineHeightPresets = [1.5, 1.8, 2.2];
  static const paragraphSpacingPresets = [0.3, 0.6, 1.0];

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

  /// 打开时阅读页不改屏幕亮度；关闭时阅读页显示期间用 [brightness]（reader「阅读页亮度」）。
  final bool brightnessFollowSystem;
  final double brightness;

  /// 实际显示的主题（设计 D14）。
  ReaderTheme effectiveTheme(Brightness platform) => followSystemDark && platform == Brightness.dark ? ReaderTheme.dark : theme;

  ReaderSettings copyWith({
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
