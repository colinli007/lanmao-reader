## ADDED Requirements

### Requirement: 隔离作用域求值
引擎 SHALL 提供隔离作用域求值：调用方给出代码和一组变量，引擎为这次求值建一个新的变量层，变量层上挂这些变量，代码以非严格模式执行，返回最后一个表达式语句的值。顶层的 `var`、函数声明、`let`/`const` 和未声明的赋值 MUST 只留在本次的变量层里，之后的求值读不到；顶层 `this` SHALL 是这个变量层。调用方 MAY 再给一个共享作用域：共享作用域里的名字对本次代码可见，但本次代码给同名变量赋值只遮蔽、不修改共享作用域；共享作用域里的函数以 `f()` 形式被调用时，`this` 是本次的变量层。共享作用域 SHALL 能由一段代码执行一次生成，之后在多次求值之间复用。调用方 MAY 让多次求值使用同一个变量层，这时变量层上的属性（包括未声明的赋值）在这些求值之间保留。外部中止信号、超时和宿主函数的语义与普通求值相同。

#### Scenario: 声明不泄漏
- **WHEN** 隔离求值 `var a = 1; function f() {} b = 2; let c = 3; a`，再隔离求值 `[typeof a, typeof f, typeof b, typeof c].join()`
- **THEN** 第一次返回 `1`，第二次返回 `undefined,undefined,undefined,undefined`

#### Scenario: 共享作用域只读遮蔽
- **WHEN** 共享作用域由 `var n = 5; function get() { return n; }` 生成，隔离求值 `n = 9; get()`
- **THEN** 返回 `5`

#### Scenario: 变量层上的变量
- **WHEN** 以变量 `{result: "abc"}` 隔离求值 `this.result + result.length`
- **THEN** 返回 `abc3`

#### Scenario: 复用变量层
- **WHEN** 以同一个变量层 `{g: 0}` 先后隔离求值 `g++; k = 1; g` 两次
- **THEN** 依次返回 `1`、`2`，第二次求值时 `k` 为 `1`
