import 'dart:convert';

import 'package:test/test.dart';

import '../tool/md3_diff/compare.dart';
import '../tool/md3_diff/debug_result.dart';

// md3-diff「解析 MD3 调试日志」「对比和分类」：日志取自 MD3 3.26.23 对白鹿书院的实际调试（正文截短）
void main() {
  const fullLog = [
    '[00:00.000] ⇒开始搜索关键字:我的',
    '[00:00.001] ︾开始解析搜索页',
    '[00:02.003] ≡获取成功:https://s.bailushuyuan.org/novel/traditional/categories/1?name_cont=%E6%88%91%E7%9A%84',
    '[00:02.015] ┌获取书籍列表',
    '[00:02.075] └列表大小:222',
    '[00:02.077] ┌获取书名',
    '[00:02.079] └我的故事',
    '[00:02.081] ┌获取作者',
    '[00:02.081] └',
    '[00:02.100] ┌获取详情页链接',
    '[00:02.121] └https://s.bailushuyuan.org/%E6%88%91%E7%9A%84%E6%95%85%E4%BA%8B',
    '[00:02.361] ◇书籍总数:222',
    '[00:02.364] ︽搜索页解析完成',
    '',
    '[00:02.365] ︾开始解析详情页',
    '[00:02.947] ┌获取书名',
    '[00:02.955] └我的故事',
    '[00:02.957] ┌获取作者',
    '[00:02.959] └琼瑶',
    '[00:02.984] ┌获取简介',
    '[00:03.002] └《我的故事》讲的是，真实人生中的琼瑶。',
    '[00:03.018] ┌获取目录链接',
    '[00:03.018] └https://s.bailushuyuan.org/%E6%88%91%E7%9A%84%E6%95%85%E4%BA%8B',
    '[00:03.018] ︽详情页解析完成',
    '',
    '[00:03.022] ︾开始解析目录页',
    '[00:03.025] ┌获取目录列表',
    '[00:03.046] └列表大小:54',
    '[00:03.058] ≡首章信息',
    '[00:03.058] ◇章节名称:缘起',
    '[00:03.058] ◇章节链接:https://s.bailushuyuan.org/novel/traditional/chapters/292837',
    '[00:03.058] ◇目录总数:54',
    '[00:03.067] ︽目录页解析完成',
    '',
    '[00:03.068] ︾开始解析正文页',
    '[00:03.692] ┌获取章节名称',
    '[00:03.693] └缘起',
    '[00:03.693] ┌获取正文内容',
    '[00:03.693] └\n　　一九八八年四月九日，我从台湾飞抵北京。\n　　且听我“从头细述”！',
    '[00:03.693] ︽正文页解析完成',
  ];

  DebugResult ours() {
    final result = DebugResult();
    result.step(DebugStep.search)
      ..ok = true
      ..fields.addAll({'count': '222', 'name': '我的故事', 'author': '', 'bookUrl': 'https://s.bailushuyuan.org/%E6%88%91%E7%9A%84%E6%95%85%E4%BA%8B'});
    result.step(DebugStep.info)
      ..ok = true
      ..fields.addAll({
        'name': '我的故事',
        'author': '琼瑶',
        'kind': '',
        'intro': '《我的故事》讲的是，\n真实人生中的琼瑶。',
        'tocUrl': 'https://s.bailushuyuan.org/%E6%88%91%E7%9A%84%E6%95%85%E4%BA%8B',
      });
    result.step(DebugStep.toc)
      ..ok = true
      ..fields.addAll({'count': '54'});
    result.step(DebugStep.content)
      ..ok = true
      ..fields.addAll({'title': '缘起', 'text': '　　一九八八年四月九日，我从台湾飞抵北京。\n　　且听我“从头细述”！'});
    return result;
  }

  group('解析 MD3 调试日志', () {
    test('完整的一次调试', () {
      final result = parseMd3Log(fullLog);
      expect(result.completed, isTrue);
      expect(result.steps[DebugStep.search]!.fields, {
        'name': '我的故事',
        'author': '',
        'bookUrl': 'https://s.bailushuyuan.org/%E6%88%91%E7%9A%84%E6%95%85%E4%BA%8B',
        'count': '222',
      });
      expect(result.steps[DebugStep.info]!.fields['author'], '琼瑶');
      // 首章信息不用（不一定是最后用的第一章），第一章看正文这一步
      expect(result.steps[DebugStep.toc]!.fields, {'count': '54'});
      expect(result.steps[DebugStep.content]!.fields['title'], '缘起');
      expect(result.steps[DebugStep.content]!.fields['text'], '\n　　一九八八年四月九日，我从台湾飞抵北京。\n　　且听我“从头细述”！');
    });

    test('出错：堆栈取第一行；没有结果；没有结束', () {
      final error = parseMd3Log([
        ...fullLog.take(14),
        '[00:02.365] ︾开始解析详情页',
        '[00:05.000] io.legado.app.exception.NoStackTraceException: 详情页出错\n\tat io.legado.app.model.webBook.BookInfo.analyzeBookInfo(BookInfo.kt:30)',
      ]);
      expect(error.progress, 1);
      expect(error.failure!.step, DebugStep.info);
      expect(error.failure!.error, 'io.legado.app.exception.NoStackTraceException: 详情页出错');

      final empty = parseMd3Log(['[00:00.001] ︾开始解析搜索页', '[00:01.000] ︽未获取到书籍']);
      expect(empty.failure!.error, '未获取到书籍');

      final unfinished = parseMd3Log(fullLog.take(28).toList());
      expect(unfinished.failure!.step, DebugStep.toc);
      expect(unfinished.failure!.error, '没有结束');
    });

    test('详情的字段按 MD3 的赋值规则补齐：空值保留搜索时的值，书名作者要 canReName', () {
      final log = [
        '[00:00.001] ︾开始解析搜索页',
        '[00:00.002] ┌获取书名', '[00:00.002] └搜索书名',
        '[00:00.002] ┌获取封面链接', '[00:00.002] └https://a.com/c.jpg',
        '[00:00.003] ︽搜索页解析完成',
        '[00:00.004] ︾开始解析详情页',
        '[00:00.005] ┌获取书名', '[00:00.005] └详情书名',
        '[00:00.005] ┌获取封面链接', '[00:00.005] └',
        '[00:00.005] ┌获取简介', '[00:00.005] └详情简介',
        '[00:00.006] ︽详情页解析完成',
      ];
      final kept = parseMd3Log(log).steps[DebugStep.info]!.fields;
      expect([kept['name'], kept['coverUrl'], kept['intro']], ['搜索书名', 'https://a.com/c.jpg', '详情简介']);
      expect(parseMd3Log(log, canReName: true).steps[DebugStep.info]!.fields['name'], '详情书名');
    });

    test('搜索的第 0 项被丢掉时：搜索的第一本不比，详情只留一定会赋值的字段', () {
      final result = parseMd3Log([
        '[00:00.001] ︾开始解析搜索页',
        '[00:00.002] ┌获取书名', '[00:00.002] └',
        '[00:00.003] ◇书籍总数:25',
        '[00:00.003] ︽搜索页解析完成',
        '[00:00.004] ︾开始解析详情页',
        '[00:00.005] ┌获取书名', '[00:00.005] └弱国无外交',
        '[00:00.005] ┌获取封面链接', '[00:00.005] └',
        '[00:00.005] ┌获取简介', '[00:00.005] └简介',
        '[00:00.006] ︽详情页解析完成',
      ]);
      expect(result.steps[DebugStep.search]!.fields, {'count': '25'});
      expect(result.steps[DebugStep.info]!.fields, {'intro': '简介'});
    });

    test('跳过详情页', () {
      final result = parseMd3Log([
        ...fullLog.take(14),
        '[00:02.365] ≡已获取目录链接,跳过详情页',
        ...fullLog.skip(25),
      ]);
      expect(result.completed, isTrue);
      expect(result.steps[DebugStep.info]!.skipped, isTrue);
    });
  });

  group('对比和分类', () {
    SourceDiff compare(DebugResult a, DebugResult b) => SourceDiff(name: '白鹿书院', url: 'https://s.bailushuyuan.org', key: '我的', ours: a, md3: b);

    test('空白不同不算不同，两边走完是一致', () {
      final diff = compare(ours(), parseMd3Log(fullLog));
      expect(diff.diffs, isEmpty);
      expect(diff.category, DiffCategory.same);
    });

    test('只有我们失败', () {
      final a = ours();
      a.steps[DebugStep.toc]!
        ..ok = false
        ..error = '目录为空';
      a.steps.remove(DebugStep.content);
      final diff = compare(a, parseMd3Log(fullLog));
      expect(diff.category, DiffCategory.oursFailed);
      expect(diff.ours.failure!.error, '目录为空');
    });

    test('字段不同：短文本直接列出，正文带长度和位置', () {
      final a = ours();
      a.steps[DebugStep.toc]!.fields['count'] = '53';
      a.steps[DebugStep.content]!.fields['text'] = '　　一九八八年四月九日，我从台湾飞抵上海。且听我“从头细述”！再加一些文字让它超过八十个字。' * 3;
      final diff = compare(a, parseMd3Log(fullLog));
      expect(diff.category, DiffCategory.fieldsDiffer);
      expect(diff.diffs.map((d) => '${d.step.label}.${d.field}'), ['目录.count', '正文.text']);
      expect(diff.diffs.first.note, isNull);
      expect(diff.diffs.last.note, contains('起不同'));
    });

    test('地址里每次都变的查询参数值不算不同，编码不同照常算', () {
      final a = ours();
      a.steps[DebugStep.info]!.fields['tocUrl'] = 'https://s.bailushuyuan.org/toc?t=1793863851102&sign=3ec7ad49';
      final b = parseMd3Log(fullLog);
      b.steps[DebugStep.info]!.fields['tocUrl'] = 'https://s.bailushuyuan.org/toc?t=1793863851762&sign=9b2de2b9';
      expect(compare(a, b).diffs, isEmpty);
      a.steps[DebugStep.info]!.fields['tocUrl'] = 'https://a.com/s?q=%C3%A5%C2%9B';
      b.steps[DebugStep.info]!.fields['tocUrl'] = 'https://a.com/s?q=%E5%9B%9E';
      expect(compare(a, b).diffs.single.field, 'tocUrl');
    });

    test('报告读回后分类和不同的字段不变（--resume）', () {
      final a = ours();
      a.steps[DebugStep.toc]!.fields['count'] = '53';
      final diff = compare(a, parseMd3Log(fullLog));
      final back = SourceDiff.fromJson(jsonDecode(jsonEncode(diff.toJson())) as Map<String, Object?>);
      expect(back.category, DiffCategory.fieldsDiffer);
      expect(back.diffs.map((d) => d.field), ['count']);
      expect(back.md3.steps[DebugStep.content]!.fields['title'], '缘起');
    });

    test('在同一步失败是都失败', () {
      final failed = parseMd3Log(['[00:00.001] ︾开始解析搜索页', '[00:01.000] ︽未获取到书籍']);
      final a = DebugResult();
      a.step(DebugStep.search).error = '搜索无结果';
      expect(compare(a, failed).category, DiffCategory.bothFailed);
    });

    test('摘要按原因归类', () {
      DebugResult failedToc(String name) {
        final a = ours();
        a.steps[DebugStep.toc]!
          ..ok = false
          ..error = '目录为空（$name ruleToc.chapterList）';
        a.steps.remove(DebugStep.content);
        return a;
      }

      final summary = markdownSummary([
        for (final name in ['甲', '乙', '丙'])
          SourceDiff(name: name, url: 'https://$name.com', key: '我的', ours: failedToc(name), md3: parseMd3Log(fullLog)),
      ], md3Version: '3.26.23', date: DateTime(2026, 11, 5));
      expect(summary, contains('| 只有我们失败 | 3 |'));
      expect(summary, contains('- 3 个｜目录｜目录为空：甲、乙、丙'));
    });
  });
}
