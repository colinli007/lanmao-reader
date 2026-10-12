import json
import os

DOC = '''<html><head>
<meta property="og:title" content="三体">
<meta property="og:image" content="/cover/1.jpg">
<meta property="og:description" content="  简介 第一段  ">
<meta property="og:novel:author" content="刘慈欣">
<meta property="og:novel:category" content="科幻">
<meta property="og:novel:status" content="完本">
<meta property="og:novel:update_time" content="2020-01-01">
<meta property="og:novel:book_name" content="三体">
<meta property="og:novel:latest_chapter_name" content="第三章">
<meta name="description" content="描述">
<title>三体</title>
</head><body>
<div class="book" id="list">
  <dl>
    <dt>最新章节</dt>
    <dd><a href="/3.html">第三章</a></dd>
    <dt>正文</dt>
    <dd><a href="/1.html">第一章</a></dd>
    <dd><a href="/2.html">第二章</a></dd>
    <div class="btm"><a>更多</a></div>
  </dl>
</div>
<div class="bookinfo"><p><i>作者</i>：<a>刘慈欣</a></p><p>分类：<a>科幻</a> 状态</p></div>
<div class="bookcover"><a href="/b/1"><img src="/c.jpg" alt="三体封面"></a></div>
<div id="chapter-content"><p>  第一段
 内容 </p><p>第二段</p><p></p><script>var s = 1;</script></div>
<div class="row">r1</div><div class="row">r2</div><div class="row">r3</div>
<ul class="info info-meta"><li><a>甲</a></li><li><a>乙</a></li></ul>
<ul class="list-chapter"><li><a href="/1">一</a></li><li class="next"><a href="/next">下一页</a></li></ul>
<h3 class="title">标题一</h3><h3 class="title">标题二</h3>
<select><option value="1" selected>1</option><option value="2">2</option><option value="3">3</option></select>
<table id="bookcon"><tr><td class="article_info_td"><div>a</div><div>b</div><div><a>c</a></div></td><td class="article_info_td"><div>x</div><div> y </div></td></tr></table>
<p class="title">段 落</p>
<a id="pt_next" href="/p2">下一页</a>
<em class="blue visible-xs">蓝</em><em class="orange visible-xs">橙</em>
<img class="lazy" data-src="/l.jpg">
<div class="item-value"><a>值</a></div>
<div class="desc-text" itemprop="description">描述<b>粗</b>尾</div>
<div class="desc-text">只有类</div>
</body></html>'''

HANDCRAFTED = [
    ('//title/text()', 'text() 取标题'),
    ('//div[@id="chapter-content"]/p/text()', 'text() 合并空白，空段落没有文本节点'),
    ('//div[@id="chapter-content"]/text()', '只有空白的文本节点得到空串'),
    ('//div[@id="chapter-content"]//text()', '递归 text() 不含脚本'),
    ('//div[@id="chapter-content"]/script/text()', '脚本的 text() 取脚本内容'),
    ('//dd/a/@href', '属性'),
    ('//dd[1]/a/text()', '下标按同名兄弟'),
    ('//dd[-1]/a/text()', '负下标'),
    ('//dd[last()]/a/text()', 'last()'),
    ('//dd[position()<3]/a/text()', 'position() 比较'),
    ('//dd[position()=1]/a/text()', 'position()=1 按字符串比较'),
    ('//dt[2]/following-sibling::dd/a/text()', '后续兄弟'),
    ('//dt[1]/following-sibling-one::*', 'following-sibling-one'),
    ('//dd[2]/preceding-sibling::*', '前面的兄弟'),
    ('//a[text()="下一页"]/@href', 'text() 比较'),
    ('//a[contains(text(),"章")]/text()', 'contains'),
    ('//a[starts-with(@href,"/1")]/@href', 'starts-with'),
    ('//option[not(@selected)]/@value', 'not'),
    ('count(//dd)', 'count'),
    ('concat("a","b")', 'concat'),
    ('string-length("中文")', 'string-length'),
    ('substring("abcdef",2,3)', 'substring'),
    ('substring("abcdef",2)', 'substring 只给两个参数'),
    ('substring-after("a=b","=")', 'substring-after'),
    ('substring-before("a=b","=")', 'substring-before'),
    ('1 + 2', '加法'),
    ('7 `mod` 3', 'mod'),
    ('//dd/a/@href | //dt/text()', '并集'),
    ('//h3/text() | //em/text()', '文本并集'),
    ('//div[@class="desc-text" and @itemprop="description"]/text()', 'and'),
    ('//div[@class="bookinfo"]/p[1]/a/text()', '嵌套下标'),
    ('/html/body/div', '绝对路径从 html 开始'),
    ('//html', '以 html 为名字'),
    ('//body/div[@class="row"][2]', '元素结果输出 HTML'),
    ('//div[@class="bookinfo"]/p/allText()', 'allText'),
    ('//div[@class="bookinfo"]/p[1]/html()', 'html()'),
    ('//div[@class="bookinfo"]/p[2]/outerHtml()', 'outerHtml()'),
    ('//p[@class="title"]/num()', 'num() 取不到'),
    ('//div[@class="row"]/num()', 'num()'),
    ('//div[@id="list"]//dd', '递归后代'),
    ('//div[@id="list"]//dl//dd', '递归包含自身'),
    ('//a/..', '父元素'),
    ('//dd/ancestor::div', 'ancestor'),
    ('//dt/self::*', 'self'),
    ('//dl/child::dt', 'child'),
    ('//a[@href~="/\\d\\.html"]/@href', '正则匹配'),
    ('//a[@href^="/"]/text()', '前缀运算符'),
    ('//*[@class="book"]', '星号'),
    ('//dd[1][1]', '多个谓词'),
    ('//dd/a/text()[1]', 'text() 的下标'),
    ('//p/text()[last()]', 'text() 的 last()'),
    ('//dd[a]', '谓词是路径'),
    ('//dd["x"]', '谓词是字符串'),
    ('//a[@nonexistent]', '属性不存在'),
    ('//div[@class="row"]/@class', '多个属性值'),
    ('//div[@id="list"]/@id', '单个属性值'),
    ('//div[@id="list"]/@missing', '单个元素缺少属性'),
    ('//normalize-space(//title)', '不支持的函数'),
    ('//a[translate(.,"a","b")]', '不支持的函数 translate'),
    ('//dd[', '语法错误'),
    ('//text', 'text 不能当名字'),
    ('//node()', 'node() 遇到有文本的元素'),
    ('//select/node()', 'node() 只有子元素'),
    ('//div[@class="row"][position() > 1]', 'position() > 1'),
    ('//div[@class="row" and position()>1]', '和 and 组合'),
]

here = os.path.dirname(os.path.abspath(__file__))
REAL = json.load(open(os.path.join(here, 'real_xpaths.json')))

CASES = (
    [('', xpath, DOC, note) for xpath, note in HANDCRAFTED]
    + [('', xpath, DOC, '书源：' + xpath) for xpath in REAL]
    + [
        ('div.bookcover', 'a/img/@src', DOC, '元素上的相对路径'),
        ('div.bookcover', '/a/@href', DOC, '元素上以 / 开头'),
        ('div.bookcover', '//img/@alt', DOC, '元素上以 // 开头'),
        ('table', 'tr/td[1]/div[3]/a/text()', DOC, '表格'),
        ('', '//td/text()', '<td>单元格</td>', '以 </td> 结尾的片段补上 tr'),
        ('', '//tr/td/text()', '<tr><td>行</td></tr>', '以 </tr> 结尾的片段补上 table'),
    ]
)
