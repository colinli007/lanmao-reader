import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanmao_reader/app_info.dart';
import 'package:lanmao_reader/settings/about_page.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  setUp(
    () => PackageInfo.setMockInitialValues(
      appName: appName,
      packageName: 'dev.lanmaoreader.app',
      version: '0.1.0',
      buildNumber: '',
      buildSignature: '',
    ),
  );

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: AboutPage())));
    await tester.pumpAndSettle();
  }

  testWidgets('显示名称、版本、协议、源代码地址和免责声明', (tester) async {
    await pump(tester);
    expect(find.text(appName), findsOneWidget);
    expect(find.text('版本 0.1.0'), findsOneWidget);
    expect(find.text('GPL-3.0'), findsOneWidget);
    expect(find.text(sourceCodeUrl), findsOneWidget);
    expect(find.text(disclaimer), findsOneWidget);
  });

  testWidgets('点源代码地址复制到剪贴板并提示', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await pump(tester);
    await tester.tap(find.text(sourceCodeUrl));
    await tester.pumpAndSettle();
    expect(copied, sourceCodeUrl);
    expect(find.text('已复制'), findsOneWidget);
  });

  testWidgets('开源许可打开第三方许可列表', (tester) async {
    await pump(tester);
    await tester.tap(find.text('开源许可'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });
}
