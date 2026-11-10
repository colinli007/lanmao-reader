## MODIFIED Requirements

### Requirement: 不支持的宿主 API
下列 API 不在本能力内：界面交互（`startBrowser`、`startBrowserAwait`、`getVerificationCode`、`openUrl`）、WebView（`webView`、`webViewGetSource`、`webViewGetOverrideUrl`）、App 配置（`getReadBookConfig`、`getThemeMode`、`getThemeConfig`）、文件与压缩包（`downloadFile`、`cacheFile`、`importScript`、`getFile`、`readFile`、`readTxtFile`、`unzipFile` 等）、字体（`queryTTF`、`replaceFont`）、简繁转换（`t2s`、`s2t`）、非对称加密与签名（`createAsymmetricCrypto`、`createSign`）、需要重新拉取书籍的 `refreshTocUrl`、`reGetBook` 和发现页的 `refreshExplore`。调用它们时 MUST 以「不支持的宿主 API」错误结束，错误里带有 API 名、书源名和字段，MUST NOT 返回空值让书源继续执行。

#### Scenario: 调用验证码
- **WHEN** 正文规则执行 `java.getVerificationCode(url)`
- **THEN** 正文链路以「不支持的宿主 API：java.getVerificationCode」错误结束

## ADDED Requirements

### Requirement: 设备编号
`java.androidId()`（三种 java 对象和书源对象都有）SHALL 返回 16 位小写十六进制文本，对应 MD3 的 ANDROID_ID。第一次调用时随机生成，存进书源级存储（不属于任何书源、不过期）；之后所有书源、所有任务 SHALL 返回同一个值，app 重启后不变。清除 app 数据或卸载重装后重新生成。

#### Scenario: 格式
- **WHEN** 规则是 `@js:java.androidId()`
- **THEN** 结果匹配 `^[0-9a-f]{16}$`

#### Scenario: 不同书源取到同一个值
- **WHEN** 书源 A 的规则先调用 `java.androidId()`，之后书源 B 的规则再调用
- **THEN** 两次结果相同
