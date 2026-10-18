## Purpose

app 的本地存储：规定哪些数据落盘、重启后怎样恢复，以及书源级状态和 Cookie 落盘后，规则引擎读到的值和内存里的一致。

## ADDED Requirements

### Requirement: 落盘的数据
系统 SHALL 把以下数据保存在本机，app 重启后恢复：书源（导入时的原始内容和启用状态）、书架上的书（包括书源 JS 和规则写入书籍的变量）、书架上每本书的目录（包括章节的变量）、书架上的书已缓存的正文、阅读进度、阅读设置、书源级状态（`cache.put` 的值及过期时间、书源变量、登录头、登录信息）、持久 Cookie。会话 Cookie、`cache.putMemory` 的值、书源日志、搜索结果 MUST NOT 落盘。

#### Scenario: 重启后书架还在
- **WHEN** 用户把一本书加入书架，读到第 5 章，然后完全退出 app 再打开
- **THEN** 书架上有这本书，打开后从第 5 章的同一位置继续，第 1 到 5 章已缓存的正文不再请求网络

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
书移出书架时，系统 SHALL 删除这本书的书籍信息、目录、正文缓存和阅读进度。书源级状态和 Cookie MUST NOT 因此被删除。

#### Scenario: 移出后再加入
- **WHEN** 用户把一本读到第 5 章的书移出书架，再从搜索结果打开它
- **THEN** 从第 1 章开始，正文重新请求网络
