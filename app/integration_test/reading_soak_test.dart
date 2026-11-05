// 连续翻页的性能与内存（add-paged-reader 任务 10.2，profile 构建）：
//   flutter drive --profile --no-dds --driver=test_driver/integration_test.dart --target=integration_test/reading_soak_test.dart \
//     -d emulator-5554 --dart-define=SOAK_MINUTES=60
// 一本 20 章、每章约八千字的合成正文（预先放进缓存，不联网）。翻页方式每 50 页轮换一次（覆盖、滑动、无动画、滚动），
// 每次轮换时从目录跳到一个不在三章窗口里的章节，量「打开已缓存章节到第一页显示」的耗时。
// 结果以 REPORT 开头打印：跳章耗时、翻页时 FrameTiming 的最大值和 99 分位、每 30 秒一次的进程 RSS、
// 每 5 分钟一次强制 GC 后的 Dart 堆（RSS 在模拟器上还含图形驱动的内存，堆的保留量才能说明排版对象有没有泄漏）。
// 读堆要直连 VM service，所以带 --no-dds（有 DDS 时 app 里拿到的是电脑上 DDS 的地址）。
// 帧耗时记进固定大小的直方图，不保存 FrameTiming 本身：一小时二十多万帧，存下来测试自己就占几十 MB。
import 'dart:developer';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lanmao_reader/online/startup.dart';
import 'package:lanmao_reader/reader/paged/paged_view.dart';
import 'package:lanmao_reader/reader/reader_page.dart';
import 'package:lanmao_reader/reader/reader_settings.dart';
import 'package:lanmao_reader/reader/scroll/scroll_view.dart';
import 'package:lanmao_reader/reader/toc_page.dart';
import 'package:lanmao_reader/storage/database.dart';
import 'package:lanmao_reader/ui/theme.dart';
import 'package:vm_service/vm_service.dart' show InstanceRef;
import 'package:vm_service/vm_service_io.dart';

const _minutes = int.fromEnvironment('SOAK_MINUTES', defaultValue: 60);

/// 对照组（--dart-define=SOAK_CONTROL=true）：同样的点击节奏和采样，但停在第一章第一页，只点中间开关菜单，
/// 不翻页、不跳章、不换翻页方式。用来区分内存增长是阅读器带来的，还是引擎、模拟器、测试框架本身的。
const _control = bool.fromEnvironment('SOAK_CONTROL');
const _bookUrl = 'local://soak';
const _chapters = 20;

/// 每次读堆时报存活实例数的类：排版结果、段落画笔和它们持有的原生段落。
const _tracked = ['ChapterLayout', 'TextSegmentPainter', 'ImageSegmentPainter', 'TextPainter', '_NativeParagraph'];

/// 合成的正文：句子长短不一，带逗号、句号、问号、对话引号和省略号。
String _chapterText(int index) {
  final random = Random(index);
  const pool = '山风谷底卷上来吹得崖边松枝簌簌作响他站在最高的那块石头望着远处渐渐亮起天色心里反复想昨夜师父说过几句话却怎么也不明白';
  String words(int n) => List.generate(n, (_) => pool[random.nextInt(pool.length)]).join();
  final paragraphs = <String>[];
  var length = 0;
  while (length < 8000) {
    final sentences = [
      for (var s = 0; s < 1 + random.nextInt(5); s++)
        switch (random.nextInt(5)) {
          0 => '${words(3)}道：“${words(4 + random.nextInt(12))}？”',
          1 => '${words(6 + random.nextInt(10))}……',
          _ => '${words(4 + random.nextInt(10))}，${words(5 + random.nextInt(14))}。',
        },
    ];
    final paragraph = sentences.join();
    paragraphs.add(paragraph);
    length += paragraph.length;
  }
  return paragraphs.join('\n');
}

typedef _ClassStats = ({String id, int bytes, int instances});

/// 进程各段内存映射的 RSS（KB），按映射名合并（匿名映射名为空）。dumpsys 只给大类，看不出是谁的映射在涨。
Map<String, int> _mappings() {
  final rss = <String, int>{};
  var name = '';
  for (final line in File('/proc/self/smaps').readAsLinesSync()) {
    if (line.startsWith('Rss:')) {
      final kb = int.parse(line.split(RegExp(r'\s+'))[1]);
      rss[name] = (rss[name] ?? 0) + kb;
    } else if (RegExp(r'^[0-9a-f]+-[0-9a-f]+ ').hasMatch(line)) {
      final fields = line.split(RegExp(r'\s+'));
      name = fields.length > 5 ? fields.sublist(5).join(' ') : '';
    }
  }
  return rss;
}

/// 毫秒耗时的直方图：0.1ms 一格，100ms 以上记在最后一格，最大值单独记。
class _Histogram {
  final _buckets = Int32List(1001);
  var _count = 0;
  var _max = 0.0;

  void add(Duration d) {
    final ms = d.inMicroseconds / 1000;
    _buckets[min((ms * 10).floor(), _buckets.length - 1)]++;
    _count++;
    _max = max(_max, ms);
  }

  int over(double ms) => _buckets.skip((ms * 10).ceil()).fold(0, (a, b) => a + b);

  double _at(double q) {
    final target = ((_count - 1) * q).round();
    var seen = 0;
    for (var i = 0; i < _buckets.length; i++) {
      seen += _buckets[i];
      if (seen > target) return i / 10;
    }
    return _max;
  }

  @override
  String toString() => '中位 ${_at(0.5).toStringAsFixed(1)}  99% ${_at(0.99).toStringAsFixed(1)}  最大 ${_max.toStringAsFixed(1)}（$_count 次）';
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  void report(String line) => debugPrint('REPORT $line');

  String stats(List<double> values) {
    final sorted = [...values]..sort();
    double at(double q) => sorted[((sorted.length - 1) * q).round()];
    return '中位 ${at(0.5).toStringAsFixed(1)}  99% ${at(0.99).toStringAsFixed(1)}  最大 ${sorted.last.toStringAsFixed(1)}（${values.length} 次）';
  }

  testWidgets('连续翻页 $_minutes 分钟', (tester) async {
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    final db = AppDatabase(NativeDatabase.memory());
    await db.saveBrowsingBook(
      const ShelfBook(
        bookUrl: _bookUrl,
        origin: 'local://',
        originName: '本地',
        name: '连续翻页',
        author: '测试',
        durChapterIndex: 0,
        durChapterPos: 0,
        inShelf: false,
        sourceData: '{}',
      ),
      [
        for (var i = 0; i < _chapters; i++)
          TocChapter(bookUrl: _bookUrl, idx: i, url: '/$i', title: '第${i + 1}章', isVolume: false, isVip: false, isPay: false, sourceData: '{}'),
      ],
    );
    await db.addToShelf(_bookUrl, DateTime(2026));
    for (var i = 0; i < _chapters; i++) {
      await db.putContent(ContentRow(bookUrl: _bookUrl, chapterUrl: '/$i', title: '第${i + 1}章', content: _chapterText(i)));
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: await startServices(database: db),
        child: MaterialApp(theme: appTheme(Brightness.light), darkTheme: appTheme(Brightness.dark), home: const ReaderPage(bookUrl: _bookUrl, startAt: 0)),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    final size = tester.getSize(find.byType(ReaderPage));
    final container = ProviderScope.containerOf(tester.element(find.byType(ReaderPage)));
    report('platform=${Platform.operatingSystem} 屏幕=${size.width.toStringAsFixed(0)}×${size.height.toStringAsFixed(0)}');

    final build = _Histogram(), raster = _Histogram(), total = _Histogram();
    void collect(List<FrameTiming> batch) {
      for (final f in batch) {
        build.add(f.buildDuration);
        raster.add(f.rasterDuration);
        total.add(f.totalSpan);
      }
    }

    SchedulerBinding.instance.addTimingsCallback(collect);

    final info = await Service.getInfo();
    final vm = await vmServiceConnectUri(info.serverWebSocketUri.toString());
    final isolate = Service.getIsolateId(Isolate.current)!;

    final opens = <double>[];
    final rss = <String>[];
    final heap = <String>[];
    // 只留数字，不留 vm_service 的响应对象：响应里带着整份 JSON，留两份堆就多出二十多 MB
    Map<String, _ClassStats>? firstClasses;
    var lastClasses = <String, _ClassStats>{};
    Map<String, int>? firstMappings;
    var lastMappings = <String, int>{};
    final watch = Stopwatch()..start();
    var nextSample = Duration.zero;
    var nextHeap = Duration.zero;
    var round = 0;
    var chapter = 0;

    /// 换翻页方式，再从目录跳到一个不在三章窗口里的章节：读缓存、排版、显示第一页，记下耗时。
    Future<void> jump(PageMode mode) async {
      container.read(readerSettingsProvider.notifier).update(container.read(readerSettingsProvider).copyWith(pageMode: mode));
      await tester.pump(const Duration(milliseconds: 300));

      final from = chapter;
      chapter = (chapter + 7) % _chapters;
      // 翻到全书末尾时会弹出「已是最后一章」，提示条会挡住菜单底栏，先清掉
      tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).clearSnackBars();
      await tester.tapAt(size.center(Offset.zero));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byTooltip('目录'));
      await tester.pump(const Duration(milliseconds: 500));
      final tile = find.descendant(of: find.byType(TocPage), matching: find.text('第${chapter + 1}章'));
      // 目录页打开时停在当前章节附近，目标绕回开头时在上面
      await tester.scrollUntilVisible(
        tile.hitTestable(),
        chapter > from ? 200 : -200,
        scrollable: find.descendant(of: find.byType(TocPage), matching: find.byType(Scrollable)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(tile);
      final open = Stopwatch()..start();
      // 只在正文视图里找（目录页里也有一行「第 N 章」）；查 widget 树而不是语义树：
      // 目录页退出的过渡期间下层的语义被屏蔽，查语义树等到的是过渡结束的时间
      final title = '第${chapter + 1}章';
      final shown = find.descendant(
        of: find.byWidgetPredicate((w) => w is PagedView || w is ScrollReaderView),
        matching: find.byWidgetPredicate((w) => w is Semantics && (w.properties.label?.startsWith(title) ?? false)),
      );
      while (shown.evaluate().isEmpty && open.elapsed < const Duration(seconds: 10)) {
        await tester.pump(const Duration(milliseconds: 5));
      }
      opens.add(open.elapsedMicroseconds / 1000);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tapAt(size.center(Offset.zero)); // 隐藏菜单
      await tester.pump(const Duration(milliseconds: 300));
    }

    while (watch.elapsed < const Duration(minutes: _minutes)) {
      final mode = PageMode.values[round % PageMode.values.length];
      if (!_control) await jump(mode);
      // 翻 50 页：分页模式点右侧，滚动模式点下方；对照组点中间
      for (var i = 0; i < 50; i++) {
        await tester.tapAt(
          _control
              ? size.center(Offset.zero)
              : mode == PageMode.scroll
              ? Offset(size.width / 2, size.height - 30)
              : Offset(size.width - 30, size.height / 2),
        );
        await tester.pump(const Duration(milliseconds: 400));
        if (watch.elapsed >= nextSample) {
          rss.add('${watch.elapsed.inSeconds}s ${(ProcessInfo.currentRss / 1048576).toStringAsFixed(1)}MB');
          nextSample += const Duration(seconds: 30);
        }
      }
      if (watch.elapsed >= nextHeap) {
        final profile = await vm.getAllocationProfile(isolate, gc: true);
        final usage = profile.memoryUsage!;
        lastClasses = {
          for (final m in profile.members!) m.classRef!.name!: (id: m.classRef!.id!, bytes: m.bytesCurrent ?? 0, instances: m.instancesCurrent ?? 0),
        };
        firstClasses ??= lastClasses;
        lastMappings = _mappings();
        firstMappings ??= lastMappings;
        String mb(int? bytes) => (bytes! / 1048576).toStringAsFixed(1);
        final counts = [for (final name in _tracked) '$name ${lastClasses[name]?.instances ?? 0}'];
        final scudo = lastMappings.entries.where((e) => e.key.startsWith('[anon:scudo:')).fold(0, (kb, e) => kb + e.value);
        heap.add(
          '${watch.elapsed.inSeconds}s 堆 ${mb(usage.heapUsage)}/${mb(usage.heapCapacity)}MB  外部 ${mb(usage.externalUsage)}MB  '
          'scudo ${(scudo / 1024).toStringAsFixed(1)}MB  ${counts.join('  ')}',
        );
        nextHeap += const Duration(minutes: 5);
      }
      round++;
    }
    SchedulerBinding.instance.removeTimingsCallback(collect);

    report('${_control ? '对照组，' : ''}$round 轮，点了 ${round * 50} 次，用时 ${watch.elapsed.inMinutes} 分钟');
    if (!_control) report('打开已缓存章节到第一页显示（毫秒）：${stats(opens)}');
    report('帧 build（毫秒）：$build');
    report('帧 raster（毫秒）：$raster');
    report('帧 总耗时（毫秒）：$total');
    // 模拟器上 raster 含等待交换缓冲区的时间（底数约 16ms，见设计「验证结果」1.5），排版和绘制的开销看 build（UI 线程）
    report('总耗时超过 16.7ms 的帧：${total.over(16.7)}（模拟器上只作参考）');
    for (final line in rss) {
      report('RSS $line');
    }
    for (final line in heap) {
      report('GC 后 $line');
    }
    // 第一次和最后一次读堆之间，存活字节数涨得最多的类，各取一个实例看是谁引用着它
    int grown(String name, int Function(_ClassStats) of) => of(lastClasses[name]!) - (firstClasses![name] == null ? 0 : of(firstClasses[name]!));
    final growth = lastClasses.keys.toList()..sort((a, b) => grown(b, (c) => c.bytes).compareTo(grown(a, (c) => c.bytes)));
    for (final name in growth.take(5)) {
      report('堆增长 $name ${(grown(name, (c) => c.bytes) / 1024).toStringAsFixed(1)}KB  ${grown(name, (c) => c.instances)} 个');
      if (grown(name, (c) => c.instances) <= 0) continue; // 只读了一次堆（运行不到 5 分钟）时没有增长
      final instances = (await vm.getInstances(isolate, lastClasses[name]!.id, 1000)).instances!;
      final path = await vm.getRetainingPath(isolate, instances.last.id!, 30);
      final steps = [
        for (final e in path.elements!)
          '${e.value is InstanceRef ? (e.value as InstanceRef).classRef?.name : e.value?.type}'
              '${e.parentField != null ? '.${e.parentField}' : ''}${e.parentListIndex != null ? '[${e.parentListIndex}]' : ''}',
      ];
      report('  引用链（${path.gcRootType}）：${steps.join(' <- ')}');
    }
    await vm.dispose();
    // 同样两次之间，RSS 涨得最多的内存映射
    int mapped(String name) => lastMappings[name]! - (firstMappings![name] ?? 0);
    final mappings = lastMappings.keys.toList()..sort((a, b) => mapped(b).compareTo(mapped(a)));
    for (final name in mappings.take(8)) {
      report('映射增长 ${name.isEmpty ? '（匿名）' : name} ${(mapped(name) / 1024).toStringAsFixed(1)}MB（现 ${(lastMappings[name]! / 1024).toStringAsFixed(1)}MB）');
    }
    await tester.pumpWidget(const SizedBox());
    await db.close();
  });
}
