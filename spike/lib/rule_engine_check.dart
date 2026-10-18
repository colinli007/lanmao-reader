/// spike 验证项：在 worker 池里对真实书源跑完整的四条链路（外网）。
library;

import 'package:blocking_bridge/blocking_bridge.dart';
import 'package:rule_engine/rule_engine.dart';

/// 搜索 → 详情 → 目录 → 第一章正文，返回各步的摘要。任何一步失败都抛出。
Future<String> runRuleEngineChains() => _runChains(_source);

/// 同上，书源是 C 类：规则里的 JS 调用 `java.ajax`、`java.base64Decode`，在 worker 里阻塞等主 isolate 的网络。
Future<String> runRuleEngineJsChains() => _runChains(_jsSource);

Future<String> _runChains(String json) async {
  final pool = WorkerPool(RuleHost().handle, size: 2);
  try {
    final source = loadBookSources(json).sources.single;
    final books = await pool.run(searchTask(source, '斗罗大陆'));
    if (books.isEmpty) throw StateError('搜索无结果');
    final book = await pool.run(bookInfoTask(source, books.first.toBook()));
    final (book: tocBook, :chapters) = await pool.run(chapterListTask(source, book));
    final first = chapters.first;
    final next = chapters.length > 1 ? chapterAbsoluteUrl(chapters[1]) : null;
    final content = await pool.run(contentTask(source, tocBook, first, nextChapterUrl: next));
    if (content.content.trim().isEmpty) throw StateError('正文为空');
    return '搜索 ${books.length} 条，《${book.name}》${chapters.length} 章，「${first.title}」正文 ${content.content.length} 字';
  } finally {
    pool.close();
  }
}

/// aoaostar/legado 里的「抖音小说」书源（A 类：POST 搜索、多页正文）。
const String _source = r'''{"bookSourceComment": "", "bookSourceGroup": "精品", "bookSourceName": "抖音小说", "bookSourceType": 0, "bookSourceUrl": "https://www.douyinxs.com/", "customOrder": -210, "enabled": true, "enabledCookieJar": false, "enabledExplore": true, "lastUpdateTime": 1687871617955, "respondTime": 5676, "ruleBookInfo": {"author": "[property=og:novel:author]@content", "coverUrl": "[property=og:image]@content", "intro": "[property=og:description]@content", "kind": "[property=og:novel:update_time]@content&&\n[property=og:novel:category]@content&&\n[property=og:novel:status]@content", "lastChapter": "[property=og:novel:lastest_chapter_name]@content##免费章节 |正文卷 |正文 |VIP章节 ", "name": "[property=og:novel:book_name]@content##|\\（.*|\\(.*|免费阅读|全文.*阅读|最新章节|小说|笔趣阁|免费.*"}, "ruleContent": {"content": "id.content@html", "nextContentUrl": "text.下一页@href"}, "ruleExplore": {}, "ruleReview": {}, "ruleSearch": {"author": "class.s4@text", "bookList": "class.novelslist2@li!0", "bookUrl": "class.s2@a@href", "coverUrl": "", "lastChapter": "class.s3@a@text", "name": "class.s2@a@text"}, "ruleToc": {"chapterList": "id.list@dd", "chapterName": "a@text", "chapterUrl": "a@href", "nextTocUrl": ""}, "searchUrl": "https://www.douyinxs.com/search/,{\n  \"body\": \"searchkey={{key}}&Submit=\",\n  \"method\": \"POST\"\n}", "weight": 0}''';

/// aoaostar/legado 里的「多看阅读①」书源（C 类：规则 JS 里用 java.ajax 取详情接口、java.base64Decode 解正文）。
const String _jsSource = r'''{"bookSourceGroup": "水幽临渊0905", "bookSourceName": "多看阅读①", "bookSourceType": 0, "bookSourceUrl": "https://www.dkmi.com/", "customOrder": 212, "enabled": true, "enabledCookieJar": false, "enabledExplore": true, "header": "{\"cookie\":\"device_id=D900MIVU7AH2SDF9;platform=wap;user_preference=%7B%7D;Hm_lvt_1c932f22da573f2870e8ab565f4ff9cb=1616847894;build=999000000;Hm_lpvt_1c932f22da573f2870e8ab565f4ff9cb=1616849443;app_id=duokan_h5;channel=Y0X66A;user_type=3\"}", "lastUpdateTime": 1692449977592, "loginUrl": "https://account.xiaomi.com/fe/service/login/password?display=mobile&sid=reader&qs", "respondTime": 4296, "ruleBookInfo": {"coverUrl": "", "kind": "$.item.tags[*]&&$.rights", "lastChapter": "$.item.latest", "name": "", "tocUrl": "$.item.fiction_id@js:\"https://www.duokan.com/store/v0/fiction/detail/\"+result+\"?chapter_id=0&_t=&_c=\"", "wordCount": "$.item.word_count"}, "ruleContent": {"content": "$.url@js:\nlet content=\"\"\nif(result){\nlet b64 = java.ajax(result)\nlet str=java.base64Decode(b64.match(/'(.+?)'/)[1])\nlet list=JSON.parse(str).p\nfor (i =0;i<list.length;i++){\ncontent+= list[i]+\"\\n\"\n}\n}else{\ncontent+=\"购买后继续阅读本章内容\"\n}\ncontent", "webJs": ""}, "ruleReview": {}, "ruleSearch": {"author": "$.role[0][1]", "bookList": "$.items[*]", "bookUrl": "$.source_id@js:\"https://www.duokan.com/hs/v0/android/fiction/book/\"+result", "checkKeyWord": "九星霸体诀", "coverUrl": "$.cover", "intro": "$.intro", "kind": "", "lastChapter": "", "name": "$.title", "wordCount": ""}, "ruleToc": {"chapterList": "$.item.toc[*]", "chapterName": "$.title", "chapterUrl": "$.seq_id@js:\n\"https://www.duokan.com/drm/v0/fiction/link?chapter_id=\"+result+\"&format=jsonp&withid=1&fiction_id=\"+baseUrl.match(/detail\\/(\\d+)/)[1]+\"&_t=&_c=\"", "isVip": "$.free@js:result?false:true"}, "searchUrl": "https://www.duokan.com/store/v0/lib/query/onebox?start=0&count=10&s={{key}}&source=2%2C5%2C6%2C7&_t=1616840245&_c=3963", "variableComment": "✱✱输入数字 变更发现列表：\n1  男榜+女榜  (默认列表)\n2  女榜+男榜\n3  仅男榜\n4  仅女榜\n5  旧的发现列表x\n✱✱若发现列表没变更，长按列表顶栏，弹出菜单选“刷新”，收起列表再摊开。", "weight": 0}''';
