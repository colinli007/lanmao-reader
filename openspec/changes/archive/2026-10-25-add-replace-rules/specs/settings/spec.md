## MODIFIED Requirements

### Requirement: 设置页入口
书架顶栏 SHALL 有「设置」按钮，点击进入设置页。设置页 SHALL 包含「替换净化规则」「正文缓存」和「关于」三项。点「替换净化规则」进入 replace-rules 的规则列表。

#### Scenario: 从书架进入设置
- **WHEN** 用户在书架点「设置」
- **THEN** 打开设置页，能看到「替换净化规则」「正文缓存」和「关于」

#### Scenario: 进入替换净化规则
- **WHEN** 用户在设置页点「替换净化规则」
- **THEN** 打开规则列表
