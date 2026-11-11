import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanmao_reader/app_info.dart';
import 'package:lanmao_reader/app_shell.dart';
import 'package:lanmao_reader/reader/reader_settings.dart';
import 'package:lanmao_reader/settings/source_feature.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../support/test_app.dart';

void main() {
  late TestServices services;
  setUp(() async {
    PackageInfo.setMockInitialValues(
      appName: appName,
      packageName: 'dev.lanmaoreader.app',
      version: '0.1.0',
      buildNumber: '',
      buildSignature: '',
    );
    services = await TestServices.create();
  });
  tearDown(() => services.db.close());

  /// [settings] 是启动时从数据库读出的设置，用来模拟重启。
  Future<void> pump(WidgetTester tester, {Map<String, String> settings = const {}}) async {
    await tester.pumpWidget(services.app(const AppShell(), overrides: [initialSettingsProvider.overrideWithValue(settings)]));
    await tester.pumpAndSettle();
  }

  Future<void> openAbout(WidgetTester tester) async {
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关于'));
    await tester.pumpAndSettle();
  }

  Future<void> tapVersion(WidgetTester tester, int times) async {
    for (var i = 0; i < times; i++) {
      await tester.tap(find.text('版本 0.1.0'));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> back(WidgetTester tester) async {
    await tester.pageBack();
    await tester.pumpAndSettle();
  }

  /// 依次切到设置和书架，检查各个在线入口。
  Future<void> expectSourceFeature(WidgetTester tester, {required bool visible}) async {
    final matcher = visible ? findsOneWidget : findsNothing;
    expect(find.byTooltip('发现'), matcher);
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.text('书源'), matcher);
    expect(find.text('替换净化规则'), matcher);
    await tester.tap(find.byTooltip('书架'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('搜索'), matcher);
    expect(find.text('去搜索'), matcher);
  }

  testWidgets('iOS 上默认关闭：没有发现 tab、搜索、书源和替换净化规则', (tester) async {
    await pump(tester);
    await expectSourceFeature(tester, visible: false);
    expect(find.text('书架还是空的'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('iOS 上连点版本 10 次打开，各入口出现，并存进数据库', (tester) async {
    await pump(tester);
    await openAbout(tester);
    await tapVersion(tester, 9);
    expect(find.text('已开启书源功能'), findsNothing);
    await tapVersion(tester, 1);
    expect(find.text('已开启书源功能'), findsOneWidget);
    expect((await services.db.loadSettings())[SourceFeatureNotifier.unlockedKey], 'true');

    await back(tester);
    await expectSourceFeature(tester, visible: true);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('iOS 上打开过以后，重启（覆盖安装）仍然打开', (tester) async {
    await pump(tester, settings: {SourceFeatureNotifier.unlockedKey: 'true'});
    await expectSourceFeature(tester, visible: true);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('iOS 上离开关于页重新计数', (tester) async {
    await pump(tester);
    await openAbout(tester);
    await tapVersion(tester, 9);
    await back(tester);
    await tester.tap(find.text('关于'));
    await tester.pumpAndSettle();
    await tapVersion(tester, 1);
    expect(find.text('已开启书源功能'), findsNothing);
    await back(tester);
    await expectSourceFeature(tester, visible: false);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('其它平台一直打开，点版本不提示', (tester) async {
    await pump(tester);
    await openAbout(tester);
    await tapVersion(tester, 10);
    expect(find.text('已开启书源功能'), findsNothing);
    await back(tester);
    await expectSourceFeature(tester, visible: true);
  }, variant: TargetPlatformVariant({TargetPlatform.android, TargetPlatform.macOS}));
}
