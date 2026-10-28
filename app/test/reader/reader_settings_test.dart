import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/reader/reader_settings.dart';

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
    );
    container.read(readerSettingsProvider.notifier).update(changed);
    final reread = ReaderSettings.fromMap(await services.db.loadSettings());
    expect(reread.toMap(), changed.toMap());
  });
}
