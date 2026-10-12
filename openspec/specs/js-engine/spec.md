# js-engine Specification

## Purpose

在 Dart 里执行书源 JS 的 quickjs-ng 绑定：JS 可以同步调用 Dart 宿主函数，宿主函数里可以再嵌套求值；求值可以因超时或外部信号中止。

## Requirements

### Requirement: 外部中止信号
求值 SHALL 可以接收一个外部中止信号，这个信号 MAY 由其它线程设置。信号被设置后，正在执行的 JS MUST 在有限时间内被中止，求值以错误结束。JS 里的 `try/catch` MUST NOT 能捕获这次中止。中止之后，引擎 MUST 仍能用于后续求值。不传中止信号时，求值行为保持不变。

#### Scenario: 中止死循环
- **WHEN** 求值 `while (true) {}`，另一个线程在 200ms 后设置中止信号
- **THEN** 求值以错误结束；随后对同一个引擎求值 `"still alive"`，能正常返回

#### Scenario: try/catch 捕获不到中止
- **WHEN** 求值 `while (true) { try { while (true) {} } catch (e) {} }`，执行中设置中止信号
- **THEN** 求值以错误结束，不会无限循环

#### Scenario: 求值开始前信号已设置
- **WHEN** 中止信号在求值开始前就已经被设置
- **THEN** 求值以错误结束，JS 代码一行也没有执行

### Requirement: 中止穿透宿主函数边界
最外层求值传入的中止信号 SHALL 对整条调用链生效，包括宿主函数里的嵌套求值。宿主函数返回 JS 时，无论正常返回还是抛出错误，只要中止信号已设置，调用它的 JS MUST 被中止，并且 MUST NOT 能被 `try/catch` 捕获。宿主函数自己吞掉了内层的中止错误也一样。

#### Scenario: 外层 JS 捕获不到嵌套求值的中止
- **WHEN** 外层 JS 执行 `try { host.nested("while (true) {}") } catch (e) {} "continued"`，其中宿主函数 `host.nested` 嵌套求值传入的代码；执行中设置中止信号
- **THEN** 内外两层求值都以错误结束，外层没有返回 `"continued"`

#### Scenario: 宿主函数吞掉中止后正常返回
- **WHEN** 宿主函数捕获了嵌套求值的中止错误，然后正常返回一个空字符串
- **THEN** 调用它的 JS 仍被中止，最外层求值以错误结束

#### Scenario: 信号在宿主函数执行期间被设置
- **WHEN** JS 执行 `try { host.wait() } catch (e) {} "continued"`；宿主函数 `host.wait` 执行期间设置中止信号，随后它抛出一个普通错误
- **THEN** 最外层求值以错误结束，没有返回 `"continued"`

### Requirement: 可中断的正则匹配
引擎 SHALL 提供与 JS 求值无关的正则接口：编译正则（语法同 JS `RegExp`，支持忽略大小写、多行、点号匹配换行等标志和 `(?i:…)` 修饰符），在字符串的指定位置查找下一个匹配，返回匹配范围和全部分组的范围（未参与匹配的分组为空）。匹配时 SHALL 可以传入外部中止信号；信号被设置后，正在进行的匹配 MUST 在有限时间内以错误结束，之后引擎和已编译的正则仍可继续使用。正则无法编译时，MUST 以带有原因的错误结束。

#### Scenario: 分组匹配
- **WHEN** 用 `(\d+)-(\d+)?` 在 `a 12- b` 里查找
- **THEN** 匹配范围是 `12-`，第 1 组是 `12`，第 2 组为空

#### Scenario: 中止灾难性回溯
- **WHEN** 用 `(a+)+b` 匹配 30 个 `a` 组成的字符串，另一个线程在 200ms 后设置中止信号
- **THEN** 匹配以错误结束；随后用同一个正则匹配 `aab`，能正常返回结果

#### Scenario: 编译失败
- **WHEN** 编译 `[未闭合`
- **THEN** 以错误结束，错误里带有失败原因

#### Scenario: 中文与代理对
- **WHEN** 用 `第(.)章` 在 `第𠀀章`（含 BMP 以外的字符）里查找，带 Unicode 标志
- **THEN** 第 1 组是完整的 `𠀀`
