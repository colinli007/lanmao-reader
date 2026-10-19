// 分页排版验证 1.1、1.2、1.3、1.6（debug，要看断言）：flutter test integration_test/typeset_test.dart -d <设备>
// 截图写到 app 的临时目录，路径以 SHOT 开头打印；测量结果以 REPORT 开头打印。
// Android 上 flutter test 结束会卸载 app，要拉截图就用 drive 并保持 app 运行，再用 run-as 拉：
//   flutter drive --keep-app-running --driver=test_driver/integration_test.dart --target=integration_test/typeset_test.dart -d <设备>
//   adb exec-out run-as dev.novelreader.spike cat code_cache/typeset_check.png > typeset_check.png
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spike/typeset/line_breaks.dart';
import 'package:spike/typeset/measure.dart';
import 'package:spike/typeset/two_pass.dart';
import 'package:spike/typeset/typeset_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  void report(String line) => debugPrint('REPORT $line');

  /// macOS 的窗口很宽，固定成手机的尺寸，和 Android 模拟器（Medium Phone，412 × 915）一致。
  void phoneSize(WidgetTester tester) {
    if (!Platform.isMacOS) return;
    tester.view.physicalSize = const Size(412, 915) * tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
  }

  testWidgets('1.1 1.2 两端对齐和缩进：三种做法的测量和截图', (tester) async {
    phoneSize(tester);
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(home: TypesetCheckPage(boundaryKey: key)));
    await tester.pumpAndSettle();
    // 占位符版本在 debug 下有没有触发 flutter#154662 的断言。
    expect(tester.takeException(), isNull);

    final view = tester.view;
    final width = view.physicalSize.width / view.devicePixelRatio - TypesetCheckPage.margin * 2;
    report('platform=${Platform.operatingSystem} width=$width dpr=${view.devicePixelRatio}');
    const style = TypesetStyle();
    for (final text in sampleParagraphs) {
      report('a  ${describe(measureFullWidthSpaces(text, style, width), width)}');
      report('b  ${describe(measureTwoPass(text, style, width), width)}');
      report('c  ${describe(measurePlaceholder(text, style, width), width)}');
    }

    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final path = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: view.devicePixelRatio);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('${Directory.systemTemp.path}/typeset_check.png');
      await file.writeAsBytes(png!.buffer.asUint8List());
      return file.path;
    });
    debugPrint('SHOT $path');
  });

  testWidgets('1.3 断行：真实网文和压力文本在五种宽度下都遵守避头尾', (tester) async {
    final corpus = parseCorpus(await rootBundle.loadString('assets/corpus.txt'));
    final paragraphs = [for (final chapter in corpus) ...chapter.paragraphs, ...stressParagraphs()];
    final violations = [
      for (final width in checkWidths) ...checkLineBreaks(paragraphs, const TypesetStyle(), width),
    ];
    report('断行检查 ${paragraphs.length} 段 × ${checkWidths.length} 种宽度，违规 ${violations.length} 处');
    for (final v in violations) {
      report('${v.kind}  ${v.char}  ${v.width}  ${v.context}');
    }
    expect(violations, isEmpty);
  });

  testWidgets('1.6 字形出框：裁剪绘制后页边露出的像素', (tester) async {
    phoneSize(tester);
    final view = tester.view;
    final width = view.physicalSize.width / view.devicePixelRatio - TypesetCheckPage.margin * 2;
    for (final lineHeight in [1.0, 1.4, 1.8]) {
      final result = await tester.runAsync(
        () => measureGlyphOverflow(TypesetStyle(lineHeight: lineHeight), width, view.devicePixelRatio),
      );
      report('行距 $lineHeight：${result!.lines} 行，相邻行伸进来 ${result.neighbor} 像素，本页首末行被裁掉 ${result.own} 像素');
    }
  });
}
