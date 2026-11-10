## Context

- `SourceRequest`（`analyze_url.dart`）照 MD3 的 `AnalyzeUrl` 构造请求：`url` 是处理完选项、转成绝对地址的地址，`_requestUrl` 是真正发出的地址（GET 编码查询串，HEAD 去掉查询串）。`fetch()` 发请求，`response()` 处理响应：`type` 不为空时正文是 `hexResponseBody`（响应字节的小写十六进制），响应地址是 `url`。
- 详情、目录第一页、正文、`java.getStrResponse()` 都经 `fetch()`；目录后续页经 `_fetchAll` 一起交给宿主；搜索分两段，请求由提交方在主 isolate 上发出。
- 正文图片（`getContentImage`）已经对 `data:` 地址不发请求，`_dataUriBytes` 要求逗号前有 `;base64`，用 Dart 的严格 `base64Decode`。
- `codec.dart` 有 `base64DecodeAndroid(text, flags)`，照 Android `Base64.decode`：字母表以外的字符跳过，`=` 位置不对时报错。

## Goals / Non-Goals

**Goals：** 带 `type` 的 `data:` 地址和 MD3 一样不发请求；图片和请求的 `data:` 解码只有一份。

**Non-Goals：**
- 目录后续页（`_fetchAll`）和搜索的两段式请求里的 `data:` 地址：MD3 能处理，但后续页地址和搜索地址写成 `data:` 没有实际用途，合集里也没见到，这次不改。
- 不带 `type` 的 `data:` 文本请求：MD3 交给 OkHttp 也会失败，保持一致。

## Decisions

### D1 判断放在 `fetch()` 里，按 MD3 的 `urlNoQuery`

MD3 的分支在 `getStrResponseAwait` 的 `type != null` 里，取字节时先试 `data:`。我们对应的位置是 `fetch()`：`type` 不为空、`data:` 能解出字节时，直接返回 `StrResponse(url: url, body: 字节的十六进制)`，和带 `type` 的网络响应形状相同（地址是请求地址），下游（`loginCheckJs`、规则）不用区分来源。

`urlNoQuery`：GET 请求时是 `url` 去掉 `?` 之后的部分，其它方法是整个 `url`，和 MD3 一致。

为什么不在宿主执行请求时处理：宿主只认 HTTP，`data:` 不是请求，在构造请求的一侧就能确定结果，也不用跨 isolate。

### D2 一个解码函数：`dataUriBytes(地址)`

放在 `analyze_url.dart`，返回 `Uint8List?`：不以 `data:` 开头或不匹配 `^data:.*?;base64,(.*)`（`.` 不跨换行，和 Kotlin 的 `Regex` 一样）时为 null；匹配时用 `base64DecodeAndroid(数据, 0)`。

正文图片改用它：地址以 `data:` 开头时调用，结果为 null 就按原来的「不支持的图片地址」报错。解码从 Dart 严格解码换成 Android 规则，多接受了空白和换行，和 MD3 一致；原来能解的地址结果不变。

十六进制复用 `hexEncode`（`codec.dart`），和 `hexResponseBody` 一样是小写。

## Risks / Trade-offs

- `data:` 数据里有 `?` 时（标准 base64 没有这个字符），GET 请求会被截断，和 MD3 一样。
