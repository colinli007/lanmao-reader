import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanmao_reader/reader/reader_settings.dart';

import '../support/test_app.dart';

void main() {
  test('默认值：字号 18、行距 1.8、亮主题、覆盖翻页、跟随系统深色', () {
    final settings = ReaderSettings.fromMap(const {});
    expect(
      (settings.fontSize, settings.lineHeight, settings.theme, settings.pageMode, settings.followSystemDark),
      (18, 1.8, ReaderTheme.light, PageMode.cover, true),
    );
  });

  test('新的四项默认值：段距 0.6、缩进 2 字、边距 20（和原来写死的一样），不常亮', () {
    final settings = ReaderSettings.fromMap(const {});
    expect((settings.paragraphSpacing, settings.indent, settings.margin, settings.keepScreenOn), (0.6, 2, 20, false));
  });

  test('新的四项：越界截到范围内，非法值回落到默认值；段距写成一位小数', () {
    final settings = ReaderSettings.fromMap(const {
      'reader.paragraphSpacing': '-1',
      'reader.indent': '9',
      'reader.margin': '2',
      'reader.keepScreenOn': 'yes',
    });
    expect((settings.paragraphSpacing, settings.indent, settings.margin, settings.keepScreenOn), (0, 4, 8, false));
    expect(const ReaderSettings(paragraphSpacing: 0.7000000000000001).toMap()['reader.paragraphSpacing'], '0.7');
  });

  test('亮度：默认跟随系统、40%；越界截到 1% 到 100%，非法值回落到默认值', () {
    final defaults = ReaderSettings.fromMap(const {});
    expect((defaults.brightnessFollowSystem, defaults.brightness), (true, 0.4));
    expect(ReaderSettings.fromMap(const {'reader.brightness': '0'}).brightness, 0.01);
    expect(ReaderSettings.fromMap(const {'reader.brightness': '1.5'}).brightness, 1.0);
    final invalid = ReaderSettings.fromMap(const {'reader.brightness': 'dim', 'reader.brightnessFollowSystem': 'no'});
    expect((invalid.brightnessFollowSystem, invalid.brightness), (true, 0.4));
  });

  test('预设：默认值是中间那个；改版前存下的非预设值照常生效，选预设后变成预设值', () {
    expect(ReaderSettings.lineHeightPresets[1], const ReaderSettings().lineHeight);
    expect(ReaderSettings.paragraphSpacingPresets[1], const ReaderSettings().paragraphSpacing);

    final old = ReaderSettings.fromMap(const {'reader.lineHeight': '2.0', 'reader.paragraphSpacing': '1.5'});
    expect((old.lineHeight, old.paragraphSpacing), (2.0, 1.5));
    expect(ReaderSettings.lineHeightPresets, isNot(contains(old.lineHeight)));
    expect(ReaderSettings.paragraphSpacingPresets, isNot(contains(old.paragraphSpacing)));

    final loose = old.copyWith(lineHeight: ReaderSettings.lineHeightPresets.last);
    expect(ReaderSettings.fromMap(loose.toMap()).lineHeight, 2.2);
  });

  test('预设落盘后读回来和预设精确相等', () {
    for (final preset in ReaderSettings.lineHeightPresets) {
      expect(ReaderSettings.fromMap(ReaderSettings(lineHeight: preset).toMap()).lineHeight, preset);
    }
    for (final preset in ReaderSettings.paragraphSpacingPresets) {
      expect(ReaderSettings.fromMap(ReaderSettings(paragraphSpacing: preset).toMap()).paragraphSpacing, preset);
    }
  });

  test('非法值回落到默认值，越界的数值截到范围内', () {
    final settings = ReaderSettings.fromMap(const {
      'reader.fontSize': '99',
      'reader.lineHeight': 'abc',
      'reader.theme': 'purple',
      'reader.pageMode': 'curl',
      'reader.followSystemDark': 'maybe',
    });
    expect(
      (settings.fontSize, settings.lineHeight, settings.theme, settings.pageMode, settings.followSystemDark),
      (ReaderSettings.maxFontSize, 1.8, ReaderTheme.light, PageMode.cover, true),
    );
  });

  test('实际主题：跟随打开且系统是深色时用暗主题，否则用选的主题', () {
    const sepia = ReaderSettings(theme: ReaderTheme.sepia);
    expect(sepia.effectiveTheme(Brightness.dark), ReaderTheme.dark);
    expect(sepia.effectiveTheme(Brightness.light), ReaderTheme.sepia);
    expect(sepia.copyWith(followSystemDark: false).effectiveTheme(Brightness.dark), ReaderTheme.sepia);
  });

  test('落盘后重读：和写进去的一样', () async {
    final services = await TestServices.create();
    addTearDown(services.db.close);
    final container = ProviderContainer(overrides: services.overrides);
    addTearDown(container.dispose);
    const changed = ReaderSettings(
      fontSize: 22,
      lineHeight: 2.1,
      theme: ReaderTheme.sepia,
      pageMode: PageMode.slide,
      followSystemDark: false,
      paragraphSpacing: 1.2,
      indent: 0,
      margin: 36,
      keepScreenOn: true,
      brightnessFollowSystem: false,
      brightness: 0.15,
    );
    container.read(readerSettingsProvider.notifier).update(changed);
    final reread = ReaderSettings.fromMap(await services.db.loadSettings());
    expect(reread.toMap(), changed.toMap());
  });
}
