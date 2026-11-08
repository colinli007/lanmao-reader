// 原生字体加载与界面验证：flutter drive --driver=test_driver/integration_test.dart \
//   --target=integration_test/reader_font_test.dart -d macos --keep-app-running
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lanmao_reader/library/providers.dart';
import 'package:lanmao_reader/reader/font_page.dart';
import 'package:lanmao_reader/reader/reader_fonts.dart';
import 'package:lanmao_reader/reader/reader_settings.dart';
import 'package:lanmao_reader/storage/database.dart';
import 'package:lanmao_reader/ui/icons.dart';
import 'package:lanmao_reader/ui/theme.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('原生加载 TTF/OTF 与打包字体字形一致，选择保存且字体页可用', (tester) async {
    final directory = await Directory.systemTemp.createTemp('reader-font-native-');
    final fonts = ReaderFonts(directory: directory);
    final db = AppDatabase(NativeDatabase.memory());
    final key = GlobalKey();
    try {
      Future<Uint8List> render(String family, int glyph) async {
        final text = TextPainter(
          text: TextSpan(text: String.fromCharCode(glyph), style: TextStyle(fontFamily: family, fontSize: 48, color: Colors.black)),
          textDirection: TextDirection.ltr,
        )..layout();
        final recorder = ui.PictureRecorder();
        text.paint(Canvas(recorder), Offset.zero);
        final picture = recorder.endRecording();
        final image = await picture.toImage(80, 80);
        final bytes = (await image.toByteData())!.buffer.asUint8List();
        image.dispose();
        picture.dispose();
        text.dispose();
        return bytes;
      }

      for (final sample in [
        (asset: 'assets/fonts/lucide.ttf', name: '测试字体.ttf', family: 'Lucide', glyph: LucideIcons.libraryBig.codePoint),
        (asset: 'fonts/MaterialIcons-Regular.otf', name: 'OpenType 字体.otf', family: 'MaterialIcons', glyph: Icons.book.codePoint),
      ]) {
        final data = await rootBundle.load(sample.asset);
        final font = await fonts.import(sample.name, data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
        final imported = await render(font.family, sample.glyph);
        final bundled = await render(sample.family, sample.glyph);
        final fallback = await render('missing-font', sample.glyph);
        expect(listEquals(imported, bundled), isTrue, reason: '${sample.name} 应与打包字体的原生字形一致');
        expect(listEquals(imported, fallback), isFalse, reason: '${sample.name} 不能只是回退字体');
      }

      await tester.pumpWidget(ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db), readerFontsProvider.overrideWith((ref) => fonts)],
        child: MaterialApp(theme: appTheme(Brightness.light), home: RepaintBoundary(key: key, child: const FontPage())),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('测试字体'));
      await tester.pumpAndSettle();
      expect(ReaderSettings.fromMap(await db.loadSettings()).fontId, fonts.entries.first.id);
      expect(tester.takeException(), isNull);
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final screenshot = File('${Directory.systemTemp.path}/reader-font-preview.png');
      await screenshot.writeAsBytes(png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes));
      image.dispose();
      debugPrint('FONT_PREVIEW ${screenshot.path}');
      await tester.tap(find.text('系统字体'));
      await tester.pumpAndSettle();
      expect(ReaderSettings.fromMap(await db.loadSettings()).fontId, isEmpty);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await db.close();
      await directory.delete(recursive: true);
    }
  });
}
