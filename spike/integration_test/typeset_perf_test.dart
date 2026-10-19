// 分页排版验证 1.4、1.5（profile）：
//   flutter drive --profile --driver=test_driver/integration_test.dart --target=integration_test/typeset_perf_test.dart -d <设备>
// 结果以 REPORT 开头打印，单位毫秒。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spike/typeset/line_breaks.dart';
import 'package:spike/typeset/turn_demo.dart';
import 'package:spike/typeset/two_pass.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  void report(String line) => debugPrint('REPORT $line');

  String stats(List<double> values) {
    final sorted = [...values]..sort();
    double at(double q) => sorted[((sorted.length - 1) * q).round()];
    final average = values.reduce((a, b) => a + b) / values.length;
    return '平均 ${average.toStringAsFixed(2)}  中位 ${at(0.5).toStringAsFixed(2)}  '
        '90% ${at(0.9).toStringAsFixed(2)}  99% ${at(0.99).toStringAsFixed(2)}  最大 ${sorted.last.toStringAsFixed(2)}';
  }

  /// 从语料里按顺序取段落，凑够 [chars] 个字。
  List<String> chapterOf(List<String> paragraphs, int chars) {
    final result = <String>[];
    var count = 0;
    for (final paragraph in paragraphs) {
      if (count >= chars) break;
      result.add(paragraph);
      count += paragraph.length;
    }
    return result;
  }

  /// 正文区域：屏幕减去安全区、页眉页脚各 28、左右边距各 20（D15）。macOS 用手机尺寸。
  Size pageSize(WidgetTester tester) {
    final view = tester.view;
    final screen = Platform.isMacOS ? const Size(412, 915) : view.physicalSize / view.devicePixelRatio;
    final padding = view.viewPadding;
    return Size(
      screen.width - 40,
      screen.height - (padding.top + padding.bottom) / view.devicePixelRatio - 56,
    );
  }

  testWidgets('1.4 排版耗时：五千字和一万字的章节', (tester) async {
    final corpus = parseCorpus(await rootBundle.loadString('assets/corpus.txt'));
    final paragraphs = [for (final chapter in corpus) ...chapter.paragraphs];
    final size = pageSize(tester);
    report('platform=${Platform.operatingSystem} 正文区域=${size.width.toStringAsFixed(1)}×${size.height.toStringAsFixed(1)}');
    const style = TypesetStyle();
    for (final chars in [5000, 10000]) {
      final chapter = chapterOf(paragraphs, chars);
      final firstPage = <double>[], whole = <double>[], disposal = <double>[];
      var pages = 0;
      for (var run = 0; run < 21; run++) {
        final laidOut = <TwoPassParagraph>[];
        final watch = Stopwatch()..start();
        paginate(chapter, style, size, maxPages: 2, onLaidOut: laidOut.add);
        final first = watch.elapsedMicroseconds / 1000;
        watch.reset();
        pages = paginate(chapter, style, size, onLaidOut: laidOut.add).length;
        final all = watch.elapsedMicroseconds / 1000;
        watch.reset();
        for (final paragraph in laidOut) {
          paragraph.dispose();
        }
        final freed = watch.elapsedMicroseconds / 1000;
        if (run == 0) {
          report('$chars 字 冷启动：排到第二页 ${first.toStringAsFixed(2)}  整章 ${all.toStringAsFixed(2)}');
          continue;
        }
        firstPage.add(first);
        whole.add(all);
        disposal.add(freed);
      }
      final count = chapter.fold(0, (sum, p) => sum + p.length);
      report('$count 字 ${chapter.length} 段 $pages 页');
      report('  排到第二页  ${stats(firstPage)}');
      report('  整章        ${stats(whole)}');
      report('  释放        ${stats(disposal)}');
    }
  });

  testWidgets('1.5 翻页帧耗时：基准、覆盖（渐变）、覆盖（BoxShadow）、滑动', (tester) async {
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    if (Platform.isMacOS) {
      tester.view.physicalSize = const Size(412, 915) * tester.view.devicePixelRatio;
      addTearDown(tester.view.resetPhysicalSize);
    }
    final corpus = parseCorpus(await rootBundle.loadString('assets/corpus.txt'));
    final paragraphs = [for (final chapter in corpus) ...chapter.paragraphs];
    for (final mode in TurnDemoMode.values) {
      final key = GlobalKey<TurnDemoState>();
      await tester.pumpWidget(MaterialApp(home: TurnDemo(key: key, paragraphs: paragraphs, mode: mode)));
      await tester.pump();
      final timings = <FrameTiming>[];
      void collect(List<FrameTiming> batch) => timings.addAll(batch);
      SchedulerBinding.instance.addTimingsCallback(collect);
      key.currentState!.play();
      await binding.delayed(const Duration(seconds: 5));
      key.currentState!.stop();
      await binding.delayed(const Duration(milliseconds: 500));
      SchedulerBinding.instance.removeTimingsCallback(collect);
      double ms(Duration d) => d.inMicroseconds / 1000;
      report('${mode.name}: ${timings.length} 帧');
      report('  build  ${stats([for (final t in timings) ms(t.buildDuration)])}');
      report('  raster ${stats([for (final t in timings) ms(t.rasterDuration)])}');
      await tester.pumpWidget(const SizedBox());
    }
  });
}
