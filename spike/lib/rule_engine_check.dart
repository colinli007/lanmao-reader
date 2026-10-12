/// spike 验证项：在 worker 池里对真实书源跑完整的四条链路（外网）。
library;

import 'package:blocking_bridge/blocking_bridge.dart';
import 'package:rule_engine/rule_engine.dart';

/// 搜索 → 详情 → 目录 → 第一章正文，返回各步的摘要。任何一步失败都抛出。
Future<String> runRuleEngineChains() async {
  final pool = WorkerPool(RuleHost().handle, size: 2);
  try {
    final source = loadBookSources(_source).sources.single;
    final books = await pool.run(searchTask(source, '斗罗大陆'));
    if (books.isEmpty) throw StateError('搜索无结果');
    final book = await pool.run(bookInfoTask(source, books.first.toBook()));
    final chapters = await pool.run(chapterListTask(source, book));
    final first = chapters.first;
    final next = chapters.length > 1 ? chapterAbsoluteUrl(chapters[1]) : null;
    final content = await pool.run(contentTask(source, book, first, nextChapterUrl: next));
    if (content.content.trim().isEmpty) throw StateError('正文为空');
    return '搜索 ${books.length} 条，《${book.name}》${chapters.length} 章，「${first.title}」正文 ${content.content.length} 字';
  } finally {
    pool.close();
  }
}

/// aoaostar/legado 里的「抖音小说」书源（A 类：POST 搜索、多页正文）。
const String _source = r'''{"bookSourceComment": "", "bookSourceGroup": "精品", "bookSourceName": "抖音小说", "bookSourceType": 0, "bookSourceUrl": "https://www.douyinxs.com/", "customOrder": -210, "enabled": true, "enabledCookieJar": false, "enabledExplore": true, "lastUpdateTime": 1687871617955, "respondTime": 5676, "ruleBookInfo": {"author": "[property=og:novel:author]@content", "coverUrl": "[property=og:image]@content", "intro": "[property=og:description]@content", "kind": "[property=og:novel:update_time]@content&&\n[property=og:novel:category]@content&&\n[property=og:novel:status]@content", "lastChapter": "[property=og:novel:lastest_chapter_name]@content##免费章节 |正文卷 |正文 |VIP章节 ", "name": "[property=og:novel:book_name]@content##|\\（.*|\\(.*|免费阅读|全文.*阅读|最新章节|小说|笔趣阁|免费.*"}, "ruleContent": {"content": "id.content@html", "nextContentUrl": "text.下一页@href"}, "ruleExplore": {}, "ruleReview": {}, "ruleSearch": {"author": "class.s4@text", "bookList": "class.novelslist2@li!0", "bookUrl": "class.s2@a@href", "coverUrl": "", "lastChapter": "class.s3@a@text", "name": "class.s2@a@text"}, "ruleToc": {"chapterList": "id.list@dd", "chapterName": "a@text", "chapterUrl": "a@href", "nextTocUrl": ""}, "searchUrl": "https://www.douyinxs.com/search/,{\n  \"body\": \"searchkey={{key}}&Submit=\",\n  \"method\": \"POST\"\n}", "weight": 0}''';
