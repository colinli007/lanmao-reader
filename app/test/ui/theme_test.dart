import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/ui/theme.dart';
import 'package:novel_reader/ui/tokens.dart';

void main() {
  Future<AppColors> colorsUnder(WidgetTester tester, Brightness platform) async {
    tester.platformDispatcher.platformBrightnessTestValue = platform;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    late AppColors colors;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        darkTheme: appTheme(Brightness.dark),
        home: Builder(
          builder: (context) {
            colors = AppColors.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    return colors;
  }

  testWidgets('浅色用图标底色作强调色', (tester) async {
    final colors = await colorsUnder(tester, Brightness.light);
    expect(colors.accent, const Color(0xFF2F5D50));
    expect(colors.background, const Color(0xFFFFFFFF));
  });

  testWidgets('深色用调亮的强调色', (tester) async {
    final colors = await colorsUnder(tester, Brightness.dark);
    expect(colors.accent, const Color(0xFF8CBFAE));
    expect(colors.background, const Color(0xFF121212));
  });

  test('背景和卡片不被强调色染色', () {
    final scheme = appTheme(Brightness.light).colorScheme;
    expect(scheme.surface, AppColors.light.background);
    expect(scheme.surfaceContainerHighest, AppColors.light.fill);
    expect(scheme.surfaceTint, Colors.transparent);
  });
}
