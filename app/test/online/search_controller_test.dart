import 'dart:async';

import 'package:blocking_bridge/blocking_bridge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/online/search_controller.dart';
import 'package:rule_engine/rule_engine.dart';

import '../support/test_app.dart';

void main() {
  late TestServices services;
  late ProviderContainer container;
  late Map<String, Completer<List<SearchBook>>> pending;
  late ProviderSubscription<SearchState> subscription;

  setUp(() async {
    services = await TestServices.create();
    container = ProviderContainer(overrides: services.overrides);
    subscription = container.listen(searchControllerProvider, (_, _) {});
    pending = {};
    services.engine.onSearch = (source, key) => (pending['${source.bookSourceUrl}|$key'] = Completer()).future;
  });
  tearDown(() async {
    subscription.close();
    container.dispose();
    await services.db.close();
  });

  SearchController controller() => container.read(searchControllerProvider.notifier);
  SearchState state() => container.read(searchControllerProvider);
  SearchBook result(String source, String name, {String author = '刘慈欣'}) =>
      SearchBook(bookUrl: '$source/$name', origin: source, originName: source)
        ..name = name
        ..author = author;
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('只在启用的、文本类、有搜索地址的书源上搜索', () async {
    await services.addSources([
      {'bookSourceUrl': 'A', 'searchUrl': '/s'},
      {'bookSourceUrl': 'B', 'searchUrl': '/s', 'enabled': false},
      {'bookSourceUrl': 'C', 'searchUrl': ' '},
      {'bookSourceUrl': 'D', 'searchUrl': '/s', 'bookSourceType': 2},
    ]);
    controller().search('  三体 ');
    expect(services.engine.calls, ['search A']);
    expect((state().key, state().total, state().running), ('三体', 1, true));
  });

  test('关键词为空不搜索；没有可用书源时提示，不发请求', () async {
    controller().search('  ');
    expect(state().total, 0);
    controller().search('三体');
    expect(state().noSources, isTrue);
    expect(services.engine.calls, isEmpty);
  });

  test('快的书源先出结果，进度逐个增加，全部完成后结束', () async {
    await services.addSources([{'bookSourceUrl': 'A', 'searchUrl': '/s'}, {'bookSourceUrl': 'B', 'searchUrl': '/s'}]);
    controller().search('三体');
    pending['A|三体']!.complete([result('A', '三体')]);
    await settle();
    expect((state().books.single.name, state().done, state().total, state().running), ('三体', 1, 2, true));
    pending['B|三体']!.complete([]);
    await settle();
    expect((state().done, state().finished), (2, true));
  });

  test('同名同作者合并，展示先完成的书源的结果', () async {
    await services.addSources([{'bookSourceUrl': 'A', 'searchUrl': '/s'}, {'bookSourceUrl': 'B', 'searchUrl': '/s'}]);
    controller().search('三体');
    pending['B|三体']!.complete([result('B', ' 三体 ')..intro = 'B 的简介']);
    pending['A|三体']!.complete([result('A', '三体')..intro = 'A 的简介', result('A', '三体', author: '别人')]);
    await settle();
    final merged = state().books;
    expect(merged, hasLength(2));
    expect([for (final r in merged.first.results) r.source.url], ['B', 'A']);
    expect(merged.first.first.intro, 'B 的简介');
  });

  test('排序：完全匹配、包含、其它三组，组内书源数多的在前，相同时先出现的在前', () async {
    await services.addSources([for (final s in ['A', 'B', 'C']) {'bookSourceUrl': s, 'searchUrl': '/s'}]);
    controller().search('三体');
    pending['A|三体']!.complete([result('A', '三体全集'), result('A', '地球往事'), result('A', '球状闪电')]);
    await settle();
    pending['B|三体']!.complete([result('B', '三体'), result('B', '地球往事')]);
    await settle();
    pending['C|三体']!.complete([result('C', '球状闪电'), result('C', '地球往事'), result('C', '三体2')]);
    await settle();
    expect([for (final b in state().books) b.name], ['三体', '三体全集', '三体2', '地球往事', '球状闪电']);
  });

  test('换关键词：旧搜索被取消，取消之后才到达的结果也不出现', () async {
    await services.addSources([{'bookSourceUrl': 'A', 'searchUrl': '/s'}, {'bookSourceUrl': 'B', 'searchUrl': '/s'}]);
    controller().search('三体');
    pending['A|三体']!.complete([result('A', '三体')]);
    await settle();
    controller().search('球状闪电');
    // 竞争：取消之后，旧任务的结果还是到了
    pending['B|三体']!.complete([result('B', '三体')]);
    pending['A|球状闪电']!.complete([result('A', '球状闪电')]);
    await settle();
    expect([for (final b in state().books) b.name], ['球状闪电']);
    expect((state().done, state().total), (1, 2));
    expect([for (final b in services.engine.batches) b.isStopped], [true, true, false, false]);
  });

  test('停止：已有结果保留，之后到达的结果不再加入', () async {
    await services.addSources([{'bookSourceUrl': 'A', 'searchUrl': '/s'}, {'bookSourceUrl': 'B', 'searchUrl': '/s'}]);
    controller().search('三体');
    pending['A|三体']!.complete([result('A', '三体')]);
    await settle();
    controller().stop();
    pending['B|三体']!.completeError(const TaskCancelledException());
    await settle();
    expect((state().books.length, state().running, state().finished), (1, false, true));
    expect(state().failures, isEmpty);
    expect(services.engine.batches.every((b) => b.isStopped), isTrue);
  });

  test('一个书源失败不影响别的；0 个结果不算失败', () async {
    await services.addSources([
      {'bookSourceUrl': 'A', 'searchUrl': '/s', 'bookSourceName': '甲'},
      {'bookSourceUrl': 'B', 'searchUrl': '/s', 'bookSourceName': '乙'},
      {'bookSourceUrl': 'C', 'searchUrl': '/s', 'bookSourceName': '丙'},
    ]);
    controller().search('三体');
    pending['A|三体']!.complete([result('A', '三体'), result('A', '三体2'), result('A', '三体3')]);
    pending['B|三体']!.completeError(UnsupportedHostApiException('java.getVerificationCode', sourceName: '乙'));
    pending['C|三体']!.complete([]);
    await settle();
    expect(state().books, hasLength(3));
    expect(state().failures, [(sourceName: '乙', reason: '不支持的宿主 API：java.getVerificationCode（乙）')]);
  });

  test('离开搜索页（provider 销毁）时取消', () async {
    await services.addSources([{'bookSourceUrl': 'A', 'searchUrl': '/s'}]);
    controller().search('三体');
    expect(services.engine.batches.single.isStopped, isFalse);
    subscription.close();
    await settle();
    expect(container.exists(searchControllerProvider), isFalse);
    expect(services.engine.batches.single.isStopped, isTrue);
  });
}
