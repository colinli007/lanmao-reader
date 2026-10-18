import '../rule/rule_data.dart';
import '../source/book_source.dart';

/// 搜索结果的一项。普通的 Dart 对象，可以在 isolate 之间传递。
final class SearchBook implements BookData {
  SearchBook({required this.bookUrl, required this.origin, required this.originName, Map<String, String>? variables})
    : variables = {...?variables};

  String bookUrl;

  /// 书源地址。
  final String origin;
  final String originName;
  @override
  String name = '';
  String author = '';
  String? kind;
  String? coverUrl;
  String? intro;
  String? wordCount;
  String? latestChapterTitle;

  /// 搜索直接命中详情页时保存这个页面，详情链路不再请求。
  String? infoHtml;

  @override
  final Map<String, String> variables;

  Book toBook() => Book(bookUrl: bookUrl, origin: origin, originName: originName, variables: variables)
    ..name = name
    ..author = author
    ..kind = kind
    ..coverUrl = coverUrl
    ..intro = intro
    ..wordCount = wordCount
    ..latestChapterTitle = latestChapterTitle
    ..infoHtml = infoHtml;

  @override
  String toString() => 'SearchBook($name, $author, $bookUrl)';
}

/// 书籍：详情、目录、正文链路的输入和输出。
final class Book implements BookData {
  Book({required this.bookUrl, required this.origin, required this.originName, Map<String, String>? variables})
    : variables = {...?variables};

  String bookUrl;
  final String origin;
  final String originName;
  @override
  String name = '';
  String author = '';
  String? kind;
  String? coverUrl;
  String? intro;
  String? wordCount;
  String? latestChapterTitle;

  /// 目录地址，详情链路取到；为空时等于书籍地址。
  String tocUrl = '';

  /// 文件类书源的下载地址。
  List<String>? downloadUrls;

  /// 详情页（搜索直接命中详情页时由搜索链路保存）。
  String? infoHtml;

  /// 目录就在详情页时保存详情页，目录链路不再请求。
  String? tocHtml;

  /// 自定义简介（JS 的 `book.upCustomIntro()` 把当前简介存到这里）。
  String? customIntro;

  /// 目录倒序（JS 的 `book.setReverseToc`），目录链路按它决定最终顺序。
  bool reverseToc = false;

  /// 章节数、当前阅读的章节序号和章节名：目录链路结束时更新章节数和当前章节名（MD3 的 BookChapterList），
  /// 书源 JS 会读它们（如按章节序号算正文地址）。
  int totalChapterNum = 0;
  int durChapterIndex = 0;
  String? durChapterTitle;

  @override
  final Map<String, String> variables;

  /// 只有书籍地址时（例如从书架打开）。
  static Book of(BookSource source, String bookUrl) =>
      Book(bookUrl: bookUrl, origin: source.bookSourceUrl, originName: source.bookSourceName);

  @override
  String toString() => 'Book($name, $author, $bookUrl)';
}

/// 章节。地址是相对目录页的原始地址（可带 `,{选项}`），正文链路才转成绝对地址。
final class BookChapter implements ChapterData {
  BookChapter({required this.bookUrl, required this.baseUrl, Map<String, String>? variables})
    : variables = {...?variables};

  final String bookUrl;

  /// 章节所在目录页的地址（重定向之后）。
  final String baseUrl;
  String url = '';
  @override
  String title = '';
  int index = 0;
  bool isVolume = false;
  bool isVip = false;
  bool isPay = false;

  /// 更新时间。
  String? tag;

  /// 正文规则取标题时，标题里拆出来的段评图片地址。
  String? reviewImg;

  @override
  final Map<String, String> variables;

  @override
  String toString() => 'BookChapter($title, $url)';
}

/// 正文链路的结果：正文，以及正文页上取到的章节名（书源有 `title` 规则时）。
final class ChapterContent {
  const ChapterContent(this.content, {required this.title, this.reviewImg});

  final String content;
  final String title;
  final String? reviewImg;
}
