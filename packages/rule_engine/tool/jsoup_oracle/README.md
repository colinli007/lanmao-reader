# 对照工具

用 MD3 锁定版本的 Java 库跑同一批用例，生成 `test/fixtures/` 下的期望值。Dart 测试逐条对照，保证行为和 MD3 一致：

- jsoup 1.16.2：文本取值、HTML 序列化、CSS 选择器（`Oracle.java`、`run.py`）；
- Jayway json-path 3.0.0（json-smart 2.6.0）：JSONPath 取值和 JSON 值转字符串（`JsonPathOracle.java`、`run_json_path.py`）；
- JsoupXpath 2.5.5：XPath 取值（`XPathOracle.java`、`run_xpath.py`），用例里包含书源中全部 A 类 XPath（`cases/real_xpaths.json`）；
- `java.net.URL`：相对地址拼接（`UrlOracle.java`、`run_url.py`）。
- jsoup 1.16.2 实体解码：`EntitiesOracle.java`、`run_entities.py`；覆盖属性模式、缺分号、HTML5 多码点实体和非法数字。`--all-entities` 可将全部实体组合与 Dart 实现逐项比较。
- 书源 JS 的编码、摘要、加解密、日期格式（`CodecOracle.java`、`run_codec.py`）：JDK（生成时用的是 Corretto 22.0.2）的 JCA、`URLEncoder`、`SimpleDateFormat`（简体中文 Locale），Hutool 5.8.22 的宽松 Base64，AOSP `android.util.Base64`（Android 15 的源码，Apache-2.0，下载后去掉两个 Android 注解）。`createSymmetricCrypto` 的密钥截断、ECB 忽略 IV、只有算法名时补全变换等规则在 `CodecOracle.java` 里按 MD3 的行为重新写了一遍；PKCS7Padding 按 Android 的提供者当作 PKCS5Padding，16 字节的 DESede 密钥按 Android 的两段密钥处理（JDK 不接受这两种写法）。

```bash
cd tool/jsoup_oracle
M=https://repo1.maven.org/maven2
curl -O $M/org/jsoup/jsoup/1.16.2/jsoup-1.16.2.jar
curl -O $M/com/jayway/jsonpath/json-path/3.0.0/json-path-3.0.0.jar
curl -O $M/net/minidev/json-smart/2.6.0/json-smart-2.6.0.jar
curl -O $M/net/minidev/accessors-smart/2.6.0/accessors-smart-2.6.0.jar
curl -O $M/org/ow2/asm/asm/9.7.1/asm-9.7.1.jar
curl -O $M/org/slf4j/slf4j-api/2.0.17/slf4j-api-2.0.17.jar
curl -O $M/cn/wanghaomiao/JsoupXpath/2.5.5/JsoupXpath-2.5.5.jar
curl -O $M/org/apache/commons/commons-lang3/3.12.0/commons-lang3-3.12.0.jar
curl -O $M/org/antlr/antlr4-runtime/4.7.2/antlr4-runtime-4.7.2.jar
curl -O $M/cn/hutool/hutool-core/5.8.22/hutool-core-5.8.22.jar
mkdir -p android/util
curl -s 'https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-15.0.0_r1/core/java/android/util/Base64.java?format=TEXT' \
  | base64 -d > android/util/Base64.java
sed -i '' -e '/UnsupportedAppUsage/d' -e '/@android.ravenwood/d' android/util/Base64.java
javac -cp '*' *.java android/util/Base64.java

python3 -I run.py cases/text_cases.py ../../test/fixtures/jsoup_text_cases.json
python3 -I run.py cases/selector_cases.py ../../test/fixtures/jsoup_selector_cases.json
python3 -I run_json_path.py cases/json_path_cases.py ../../test/fixtures/json_path_cases.json
python3 -I run_xpath.py cases/xpath_cases.py ../../test/fixtures/xpath_cases.json
python3 -I run_url.py cases/url_cases.py ../../test/fixtures/url_cases.json
python3 -I run_entities.py ../../test/fixtures/jsoup_entities_cases.json --all-entities
python3 -I run_codec.py cases/codec_cases.py ../../test/fixtures/codec_cases.json
```

各脚本的用例格式写在脚本开头的说明里。
