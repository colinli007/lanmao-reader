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
    this.volumeKeyTurn = true,
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
    volumeKeyTurn: bool.tryParse(map[_volumeKeyTurn] ?? '') ?? true,
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

  static const _fontSize = 'reader.fontSize';
  static const _lineHeight = 'reader.lineHeight';
  static const _theme = 'reader.theme';
  static const _pageMode = 'reader.pageMode';
  static const _followSystemDark = 'reader.followSystemDark';
  static const _paragraphSpacing = 'reader.paragraphSpacing';
  static const _indent = 'reader.indent';
  static const _margin = 'reader.margin';
  static const _keepScreenOn = 'reader.keepScreenOn';
  static const _volumeKeyTurn = 'reader.volumeKeyTurn';

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

  /// Android 上用音量键翻页（reader「音量键翻页」）。
  final bool volumeKeyTurn;

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
    bool? volumeKeyTurn,
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
    volumeKeyTurn: volumeKeyTurn ?? this.volumeKeyTurn,
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
    _volumeKeyTurn: '$volumeKeyTurn',
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
