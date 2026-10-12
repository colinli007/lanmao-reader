# 对照工具

用 MD3 锁定版本的 Java 库跑同一批用例，生成 `test/fixtures/` 下的期望值。Dart 测试逐条对照，保证行为和 MD3 一致：

- jsoup 1.16.2：文本取值、HTML 序列化、CSS 选择器（`Oracle.java`、`run.py`）；
- Jayway json-path 3.0.0（json-smart 2.6.0）：JSONPath 取值和 JSON 值转字符串（`JsonPathOracle.java`、`run_json_path.py`）；
- JsoupXpath 2.5.5：XPath 取值（`XPathOracle.java`、`run_xpath.py`），用例里包含书源中全部 A 类 XPath（`cases/real_xpaths.json`）；
- `java.net.URL`：相对地址拼接（`UrlOracle.java`、`run_url.py`）。

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
javac -cp '*' *.java

python3 -I run.py cases/text_cases.py ../../test/fixtures/jsoup_text_cases.json
python3 -I run.py cases/selector_cases.py ../../test/fixtures/jsoup_selector_cases.json
python3 -I run_json_path.py cases/json_path_cases.py ../../test/fixtures/json_path_cases.json
python3 -I run_xpath.py cases/xpath_cases.py ../../test/fixtures/xpath_cases.json
python3 -I run_url.py cases/url_cases.py ../../test/fixtures/url_cases.json
```

各脚本的用例格式写在脚本开头的说明里。
