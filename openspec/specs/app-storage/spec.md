# app-storage Specification

## Purpose

app 的本地存储：规定哪些数据落盘、重启后怎样恢复，以及书源级状态和 Cookie 落盘后，规则引擎读到的值和内存里的一致。

## Requirements

### Requirement: 落盘的数据
系统 SHALL 把以下数据保存在本机，app 重启后恢复：书源（导入时的原始内容和启用状态）、书架上的书（包括书源 JS 和规则写入书籍的变量）、书架上每本书的目录（包括章节的变量）、书架上的书已缓存的正文（含正文图片）、阅读进度、阅读设置、替换规则（导入或编辑后的内容和启用状态）、搜索历史（关键词、使用次数、最后使用时间）、书源级状态（`cache.put` 的值及过期时间、书源变量、登录头、登录信息）、持久 Cookie。会话 Cookie、`cache.putMemory` 的值、书源日志、搜索结果 MUST NOT 落盘。

#### Scenario: 重启后书架还在
- **WHEN** 用户把一本书加入书架，读到第 5 章，然后完全退出 app 再打开
- **THEN** 书架上有这本书，打开后从第 5 章的同一位置继续，第 1 到 5 章已缓存的正文不再请求网络

#### Scenario: 重启后替换规则还在
- **WHEN** 用户导入 3 条替换规则，停用其中一条，然后完全退出 app 再打开
- **THEN** 规则列表里仍是这 3 条，那一条仍是停用

#### Scenario: 重启后搜索历史还在
- **WHEN** 用户搜索「三体」两次、「斗罗」一次，然后完全退出 app 再打开
- **THEN** 搜索历史里有这两个词，「三体」的使用次数是 2

#### Scenario: 升级后数据还在
- **WHEN** 用户从没有替换规则的版本升级到这个版本
- **THEN** 书源、书架、进度、正文缓存、设置都还在，替换规则列表为空

#### Scenario: 从没有搜索历史的版本升级
- **WHEN** 用户从没有搜索历史的版本升级到这个版本
- **THEN** 原有的数据都还在，搜索历史为空，之后的搜索能记下

#### Scenario: 搜索结果不保留
- **WHEN** 用户搜索后退出 app 再打开
- **THEN** 搜索页没有上一次的结果

### Requirement: 书源级状态读写即时可见
书源 JS 写入的书源级状态 SHALL 写入后立即对所有 worker 可见，不等落盘完成；落盘在后台按写入顺序进行。落盘失败 MUST 只记录到书源日志，不影响本次运行中的读写。带过期时间的值过期后，无论是否重启，读取 SHALL 返回 null。

#### Scenario: 重启后读到未过期的缓存
- **WHEN** 书源 JS 执行 `cache.put('k', 'v', 600)`，1 分钟后重启 app，书源 JS 执行 `cache.get('k')`
- **THEN** 结果为 `v`

#### Scenario: 重启后过期的值读不到
- **WHEN** 书源 JS 执行 `cache.put('k', 'v', 1)`，2 秒后重启 app，书源 JS 执行 `cache.get('k')`
- **THEN** 结果为 null

#### Scenario: 书源变量和登录头
- **WHEN** 书源 JS 执行 `source.setVariable('x')` 和 `source.putLoginHeader('{"Authorization":"t"}')`，重启 app 后该书源发出请求
- **THEN** `source.getVariable()` 返回 `x`，请求头带有 `Authorization: t`

### Requirement: 持久 Cookie
响应里带 `Expires` 或 `Max-Age` 的 Cookie，以及书源 JS 通过 `cookie.setCookie`、`cookie.replaceCookie`、`source.putLoginHeader` 写入的 Cookie，SHALL 在重启后仍随该域名的请求发送。会话 Cookie 重启后 MUST NOT 再发送。`cookie.removeCookie` 删除的 Cookie 重启后 MUST NOT 恢复。Cookie 的匹配与合并规则不变（见 source-request 的「跨 worker 共享 Cookie」）。

#### Scenario: 持久 Cookie 跨重启
- **WHEN** 书源开启 `enabledCookieJar`，响应带 `Set-Cookie: sid=1; Max-Age=86400`，重启 app 后该书源发出请求
- **THEN** 请求带有 `sid=1`

#### Scenario: 会话 Cookie 不跨重启
- **WHEN** 响应带 `Set-Cookie: tmp=1`（没有 Expires 和 Max-Age），重启 app 后该书源发出请求
- **THEN** 请求不带 `tmp=1`

#### Scenario: 删除后不恢复
- **WHEN** 书源 JS 执行 `cookie.removeCookie('https://a.com')`，然后重启 app
- **THEN** 发往 `a.com` 的请求不带之前保存的 Cookie

### Requirement: 不在书架上的书
不在书架上的书可以阅读，它的目录、正文和阅读进度在本次运行中可用，app 重启后 MUST NOT 保留。用户把它加入书架时，系统 SHALL 把当时的书籍信息、目录、已加载的正文和阅读进度一起保留下来。

#### Scenario: 没加书架的书重启后不保留
- **WHEN** 用户从搜索结果打开一本书读到第 3 章，没有加入书架，重启 app 后再从搜索结果打开它
- **THEN** 从第 1 章开始，正文重新请求网络

#### Scenario: 先读后加书架
- **WHEN** 用户从搜索结果打开一本书读到第 3 章，然后加入书架，再重启 app
- **THEN** 书架上这本书的进度是第 3 章，第 1 到 3 章已加载的正文不再请求网络

### Requirement: 移出书架时清理
书移出书架时，系统 SHALL 删除这本书的书籍信息、目录、正文缓存（含正文图片）和阅读进度。书源级状态和 Cookie MUST NOT 因此被删除。

#### Scenario: 移出后再加入
- **WHEN** 用户把一本读到第 5 章的书移出书架，再从搜索结果打开它
- **THEN** 从第 1 章开始，正文重新请求网络

### Requirement: 换书源时的数据
书架上的书换书源成功时，系统 SHALL 在一次写入里完成下面这些变化，中途失败时全部不生效。

- **删除**：旧书源的书籍信息、目录和已缓存的正文。
- **保存**：新书源的书籍信息和目录，作为书架上的书，包括书源 JS 和规则写入书籍、章节的变量。
- **保留**：
  - 书的加入时间和最近阅读时间。
  - 阅读进度，按 bookshelf 的「换书源后定位当前章节」对齐后写入。
  - 新书源上这本书已经缓存的正文。比如用户以前从搜索结果打开过它、读过几章，但没有加入书架，这些正文在本次运行中还在。
- **不变**：书源级状态和 Cookie MUST NOT 因此被删除或改变。

#### Scenario: 换源后重启
- **WHEN** 书架上的书从书源 A 换到书源 C 后，用户完全退出 app 再打开
- **THEN** 书架上只有来自书源 C 的这本书，进度是换源时对齐到的章节和位置

#### Scenario: 旧书源的正文缓存被删除
- **WHEN** 书源 A 上这本书的第 1 到 5 章已缓存，换到书源 C
- **THEN** 存储里不再有书源 A 这本书的正文，正文缓存的章节数相应减少

#### Scenario: 新书源已缓存的正文保留
- **WHEN** 用户在本次运行中从搜索结果打开过书源 C 的这本书，读过第 1 章但没有加入书架，然后把书架上来自书源 A 的同一本书换到书源 C
- **THEN** 换源后读第 1 章时不再请求网络

#### Scenario: 书源级状态不变
- **WHEN** 书源 A 的 JS 执行过 `cache.put('k', 'v', 600)`，书架上的书从书源 A 换到书源 C 后，书源 A 的 JS 执行 `cache.get('k')`
- **THEN** 结果为 `v`

### Requirement: 清除正文缓存
用户清除正文缓存时，系统 SHALL 删除所有书的已缓存正文和正文图片，包括书架上的书和本次运行中浏览中的书，并回收它们占用的磁盘空间。书籍信息、目录、阅读进度、书源、阅读设置、替换规则、书源级状态和 Cookie MUST NOT 因此被删除或改变。清除后阅读被清掉的章节时，SHALL 重新请求网络，并照常缓存新取到的正文。

#### Scenario: 清除后重新请求网络
- **WHEN** 一本书读到第 5 章，第 1 到 5 章已缓存，用户清除正文缓存后从书架打开这本书
- **THEN** 停在第 5 章的同一位置，第 5 章的正文重新请求网络

#### Scenario: 清除不影响书架和进度
- **WHEN** 书架上有两本书，用户清除正文缓存后重启 app
- **THEN** 书架上仍是这两本书，目录、未读章节数和阅读进度都不变

#### Scenario: 清除不影响书源级状态
- **WHEN** 书源 JS 执行过 `cache.put('k', 'v', 600)`，用户清除正文缓存后书源 JS 执行 `cache.get('k')`
- **THEN** 结果为 `v`

#### Scenario: 清除不影响替换规则
- **WHEN** 有 3 条替换规则，用户清除正文缓存
- **THEN** 规则列表不变

#### Scenario: 磁盘空间被回收
- **WHEN** 已缓存的正文共 10MB，用户清除正文缓存
- **THEN** 数据库文件的大小减少约 10MB

#### Scenario: 图片一起清除
- **WHEN** 一本书第 3 章的插图已缓存，用户清除正文缓存后打开第 3 章
- **THEN** 正文和插图都重新请求网络
