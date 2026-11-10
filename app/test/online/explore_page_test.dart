import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanmao_reader/online/book_detail_page.dart';
import 'package:lanmao_reader/online/explore_books_page.dart';
import 'package:lanmao_reader/online/explore_page.dart';
import 'package:rule_engine/rule_engine.dart';

import '../support/test_app.dart';

// explore 的场景：发现页的书源、展开分类、分类书籍页
void main() {
  late TestServices services;
  setUp(() async => services = await TestServices.create());
  tearDown(() => services.db.close());

  Map<String, Object?> source(String url, String name, [Map<String, Object?> extra = const {}]) => {
    'bookSourceUrl': url,
    'bookSourceName': name,
    'exploreUrl': '玄幻::/xh/{{page}}',
    ...extra,
  };

  const kinds = [
    ExploreKind('排行', style: FlexStyle(basisPercent: 1, grow: 1)),
    ExploreKind('玄幻', url: '/xh/{{page}}', style: FlexStyle(basisPercent: 0.25, grow: 1)),
    ExploreKind('排序', type: 'select'),
  ];

  SearchBook book(String url, String name) => SearchBook(bookUrl: url, origin: 'https://e.com', originName: '发现源')
    ..name = name
    ..author = '作者$name'
    ..intro = '$name的简介';

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(services.app(const ExplorePage()));
    await tester.pumpAndSettle();
  }

  int kindCalls() => services.engine.calls.where((call) => call.startsWith('kinds')).length;

  group('发现页的书源', () {
    testWidgets('只列出启用、文本类、没关掉发现、有发现地址的书源，可以按名称和分组筛选', (tester) async {
      await services.addSources([
        source('https://e.com', '发现源'),
        source('https://b.com', '停用的', {'enabled': false}),
        source('https://c.com', '关掉发现的', {'enabledExplore': false}),
        source('https://d.com', '漫画', {'bookSourceType': 2}),
        source('https://f.com', '没有发现地址', {'exploreUrl': ' '}),
        source('https://g.com', '另一个', {'bookSourceGroup': '男频,精品'}),
      ]);
      await pump(tester);
      expect(find.text('发现源'), findsOneWidget);
      expect(find.text('另一个'), findsOneWidget);
      for (final name in ['停用的', '关掉发现的', '漫画', '没有发现地址']) {
        expect(find.text(name), findsNothing);
      }

      await tester.enterText(find.byType(TextField), '男频');
      await tester.pump();
      expect(find.text('发现源'), findsNothing);
      expect(find.text('另一个'), findsOneWidget);
    });

    testWidgets('没有能发现的书源时说明去哪里导入', (tester) async {
      await pump(tester);
      expect(find.text('没有可以发现的书源，先在「设置 → 书源」里导入或启用'), findsOneWidget);
    });
  });

  group('展开书源的分类', () {
    testWidgets('展开显示分类，再次展开不重新计算；展开另一个时收起之前的', (tester) async {
      await services.addSources([source('https://e.com', '发现源'), source('https://g.com', '另一个')]);
      services.engine.onExploreKinds = (source) async => kinds;
      await pump(tester);

      await tester.tap(find.text('发现源'));
      await tester.pumpAndSettle();
      expect(find.text('排行'), findsOneWidget);
      expect(find.text('玄幻'), findsOneWidget);
      expect(find.text('排序'), findsOneWidget);

      await tester.tap(find.text('发现源'));
      await tester.pumpAndSettle();
      expect(find.text('玄幻'), findsNothing);
      await tester.tap(find.text('发现源'));
      await tester.pumpAndSettle();
      expect(find.text('玄幻'), findsOneWidget);
      expect(kindCalls(), 1);

      await tester.tap(find.text('另一个'));
      await tester.pumpAndSettle();
      expect(find.text('玄幻'), findsOneWidget);
      expect(kindCalls(), 2);
      expect(services.engine.calls.last, 'kinds https://g.com');
    });

    testWidgets('小标题和交互式分类点了没有反应', (tester) async {
      await services.addSources([source('https://e.com', '发现源')]);
      services.engine.onExploreKinds = (source) async => kinds;
      await pump(tester);
      await tester.tap(find.text('发现源'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('排行'));
      await tester.tap(find.text('排序'));
      await tester.pumpAndSettle();
      expect(find.byType(ExploreBooksPage), findsNothing);
    });

    testWidgets('没有样式的分类按文字宽度排，文字不被省略', (tester) async {
      await services.addSources([source('https://e.com', '发现源')]);
      services.engine.onExploreKinds = (source) async => const [
        ExploreKind('------ 分 类 ------'),
        ExploreKind('玄幻', url: '/xh'),
        ExploreKind('全部完结小说', url: '/wb'),
      ];
      await pump(tester);
      await tester.tap(find.text('发现源'));
      await tester.pumpAndSettle();
      for (final title in ['------ 分 类 ------', '玄幻', '全部完结小说']) {
        expect(tester.renderObject<RenderParagraph>(find.text(title)).didExceedMaxLines, isFalse, reason: title);
      }
    });

    testWidgets('没有分类时说明', (tester) async {
      await services.addSources([source('https://e.com', '发现源')]);
      services.engine.onExploreKinds = (source) async => const [];
      await pump(tester);
      await tester.tap(find.text('发现源'));
      await tester.pumpAndSettle();
      expect(find.text('没有分类'), findsOneWidget);
    });

    testWidgets('出错时显示原因，点「重试」重新计算', (tester) async {
      await services.addSources([source('https://e.com', '发现源')]);
      var attempts = 0;
      services.engine.onExploreKinds = (source) async => ++attempts == 1 ? throw RuleException('发现地址不是合法的 JSON') : kinds;
      await pump(tester);
      await tester.tap(find.text('发现源'));
      await tester.pumpAndSettle();
      expect(find.textContaining('发现地址不是合法的 JSON'), findsOneWidget);

      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('玄幻'), findsOneWidget);
      expect(attempts, 2);
    });
  });

  group('分类书籍页', () {
    Future<void> openKind(WidgetTester tester) async {
      await services.addSources([source('https://e.com', '发现源')]);
      services.engine.onExploreKinds = (source) async => kinds;
      await pump(tester);
      await tester.tap(find.text('发现源'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('玄幻'));
      await tester.pumpAndSettle();
    }

    testWidgets('按页取，去掉重复的书，没有新书时到底', (tester) async {
      services.engine.onExplore = (source, url, page) async => switch (page) {
        1 => [book('/b/1', '甲'), book('/b/2', '乙')],
        2 => [book('/b/2', '乙'), book('/b/3', '丙')],
        _ => [book('/b/3', '丙')],
      };
      await openKind(tester);
      expect(find.byType(ExploreBooksPage), findsOneWidget);
      expect(find.widgetWithText(AppBar, '玄幻'), findsOneWidget);
      expect(find.text('甲'), findsOneWidget);
      expect(find.text('丙'), findsOneWidget);
      expect(find.text('乙'), findsOneWidget);
      expect(find.text('作者甲'), findsOneWidget);
      expect(find.text('甲的简介'), findsOneWidget);
      expect(find.text('没有更多了'), findsOneWidget);
      expect(services.engine.calls.where((call) => call.startsWith('explore')), [
        'explore /xh/{{page}} 1',
        'explore /xh/{{page}} 2',
        'explore /xh/{{page}} 3',
      ]);
    });

    testWidgets('滑到底部时才取下一页', (tester) async {
      services.engine.onExplore = (source, url, page) async => [for (var i = 0; i < 20; i++) book('/b/$page/$i', '书$page-$i')];
      await openKind(tester);
      expect(services.engine.calls.where((call) => call.startsWith('explore')), hasLength(1));

      await tester.fling(find.byType(ListView), const Offset(0, -3000), 3000);
      await tester.pumpAndSettle();
      expect(services.engine.calls.where((call) => call.startsWith('explore')).length, greaterThan(1));
    });

    testWidgets('第一页没有书', (tester) async {
      services.engine.onExplore = (source, url, page) async => const [];
      await openKind(tester);
      expect(find.text('没有取到书，可能是网站拦截了请求，或者书源规则已经失效'), findsOneWidget);
    });

    testWidgets('出错时显示原因，点「重试」重新取这一页', (tester) async {
      var attempts = 0;
      services.engine.onExplore = (source, url, page) async =>
          ++attempts == 1 ? throw RuleException('列表规则出错') : (page == 1 ? [book('/b/1', '甲')] : const <SearchBook>[]);
      await openKind(tester);
      expect(find.textContaining('列表规则出错'), findsOneWidget);

      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('甲'), findsOneWidget);
      expect(find.text('没有更多了'), findsOneWidget);
      expect(services.engine.calls.where((call) => call.startsWith('explore')), [
        'explore /xh/{{page}} 1',
        'explore /xh/{{page}} 1',
        'explore /xh/{{page}} 2',
      ]);
    });

    testWidgets('点一本书打开详情页', (tester) async {
      await services.useSimpleBook();
      services.engine.onExplore = (source, url, page) async => page == 1 ? [book('/b/1', '甲')] : const <SearchBook>[];
      await openKind(tester);
      await tester.tap(find.text('甲'));
      await tester.pumpAndSettle();
      expect(find.byType(BookDetailPage), findsOneWidget);
      expect(services.engine.calls, contains('info /b/1'));
    });
  });
}
