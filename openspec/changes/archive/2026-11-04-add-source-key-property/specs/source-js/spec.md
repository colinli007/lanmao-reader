## MODIFIED Requirements

### Requirement: 书籍、章节和书源对象
`book`、`chapter`、`source` SHALL 以对象形式提供 MD3 bean 的同名属性（如 `book.name`、`book.author`、`book.bookUrl`、`book.durChapterTitle`、`chapter.title`、`chapter.index`、`source.bookSourceUrl`、`source.bookSourceComment`）和下面「宿主 API」里列出的方法。Rhino 把无参 getter 当成同名属性，所以 `source` 还 SHALL 有 `key`（书源地址，同 `getKey()`）和 `tag`（书源名，同 `getTag()`）。给 `book` 的属性赋值 SHALL 写回书籍并随链路结果返回；给 `chapter`、`source` 的属性赋值 MUST 被忽略，属性值不变。

#### Scenario: 修改书名
- **WHEN** 详情的简介规则里执行 `book.name = '新名'; result`
- **THEN** 详情链路返回的书名是 `新名`

#### Scenario: 章节只读
- **WHEN** 目录项规则里执行 `chapter.title = 'x'; chapter.title`
- **THEN** 结果是原来的章节名

#### Scenario: 书源的 key 和 tag
- **WHEN** 书源地址是 `https://www.a.com`、书源名是 `测试源`，搜索地址里执行 `source.key + source.tag`
- **THEN** 结果是 `https://www.a.com测试源`
