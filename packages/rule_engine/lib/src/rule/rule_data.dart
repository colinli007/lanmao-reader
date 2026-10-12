/// 能保存 `@put` 变量的对象：书籍、章节，以及本次链路的临时数据。对应 MD3 的 `RuleDataInterface`。
abstract interface class RuleData {
  Map<String, String> get variables;
}

/// 书籍：`@get:{bookName}` 读取书名。
abstract interface class BookData implements RuleData {
  String get name;
}

/// 章节：`@get:{title}` 读取章节名。
abstract interface class ChapterData implements RuleData {
  String get title;
}

/// 本次链路的临时变量（MD3 的 `RuleData`），没有书籍和章节时 `@put` 写到这里。
final class ChainData implements RuleData {
  @override
  final Map<String, String> variables = {};
}
