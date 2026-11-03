// 系统字体下检查分页绘制（add-paged-reader 任务 4.1，debug 构建，要看断言）：
//   flutter test integration_test/page_glyph_test.dart -d macos     # 或 -d emulator-5554
// 截图路径以 SHOT 开头打印。Android 上测试结束会卸载 app，截图跟着删掉；最后那一页会全屏显示 10 秒，
// 看到 SHOWING 后用 adb exec-out screencap -p > page.png 截屏。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lanmao_reader/reader/chapter_format.dart';
import 'package:lanmao_reader/reader/layout/chapter_layout.dart';
import 'package:lanmao_reader/reader/layout/page_painter.dart';
import 'package:lanmao_reader/reader/reader_settings.dart';

/// 每隔几个字放一个 emoji 或生僻字（会用回退字体），行距 1.0 时它们会伸出行盒。
const _text =
    '他抬头😀看见𠀀天边𪚥升起一道🎉光芒，𡘙山谷里👨‍👩‍👧回荡着𠮷的笑声，龘龘靐齉🌕月色照在𩸽鱼身上，'
    'Ǻǻ Ṩṩ ÅÉ 的字母也在这里，🐉龙吟𠀋声声，𪜶们𠆢一起𤴓走向远方😭，最后𠂇又回到了起点🙏。';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('行距 1.0、页首页尾都有 emoji：每页都能画出来，页内 painter 的断行和量出来的一致', (tester) async {
    const size = Size(412, 915);
    final insets = PageGeometry.bodyInsets(const EdgeInsets.only(top: 24, bottom: 16), 20);
    final chapter = formatChapter('第一章 字形', List.filled(30, _text).join('\n'));
    final layout = ChapterLayout(chapter, LayoutSpec(fontSize: 18, lineHeight: 1.0, size: insets.deflateSize(size)))
      ..layoutThrough(1 << 30);

    Future<ui.Image> render(int index) {
      final recorder = ui.PictureRecorder();
      PagePainter(layout: layout, index: index, theme: ReaderTheme.light, insets: insets).paint(Canvas(recorder), size);
      return recorder.endRecording().toImage(size.width.toInt() * 2, size.height.toInt() * 2);
    }

    // debug 下 painterFor 会断言页内 painter 的断行和切页时量的一致
    for (var i = 0; i < layout.pages.length; i++) {
      (await tester.runAsync(() => render(i)))!.dispose();
    }
    final split = layout.pages.indexWhere(
      (page) => page.segments.first.from > 0 && page.segments.last.to < layout.linesOf(page.segments.last.paragraph).lines.length,
    );
    expect(split, greaterThan(0));
    final path = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..scale(2);
      PagePainter(layout: layout, index: split, theme: ReaderTheme.light, insets: insets).paint(canvas, size);
      final image = await recorder.endRecording().toImage(size.width.toInt() * 2, size.height.toInt() * 2);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('${Directory.systemTemp.path}/page_glyph.png');
      await file.writeAsBytes(png!.buffer.asUint8List());
      return file.path;
    });
    debugPrint('SHOT $path（第 ${split + 1} 页，共 ${layout.pages.length} 页）');

    await tester.pumpWidget(
      CustomPaint(
        size: Size.infinite,
        painter: PagePainter(layout: layout, index: split, theme: ReaderTheme.light, insets: insets),
      ),
    );
    debugPrint('SHOWING');
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 10)));
    await tester.pumpWidget(const SizedBox());
    layout.dispose();
  });
}
