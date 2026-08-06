# 模块阶段门模板

每个编号模块在编写 RTL 前，都必须复制并填写本模板。

## 1. 架构冻结

- 模块职责：
- 明确不负责的功能：
- 内部数据通路与状态机：
- 缓冲区深度和溢出策略：
- 时钟域与复位域：
- 错误处理和可观测性：
- 依赖项与行为级 Partner Model：

## 2. 接口冻结

对每个端口记录方向、位宽、所属时钟、复位值、Ready/Valid 规则、字节序、
合法编码、最大延迟、Backpressure 和错误行为。

## 3. RTL 前仿真计划

- 参考模型：
- 测试平台拓扑：
- Directed Case：
- 约束随机维度：
- 错误注入：
- Assertion：
- 功能覆盖点：
- 要求的随机种子和迭代次数：
- 通过/失败标准：

## 4. 测试平台激活

- Driver、Monitor、参考模型和 Scoreboard 必须先于 RTL 建立。
- 使用故意错误的 Stub DUT 运行至少一个预期失败用例，证明 Checker 能观察
  到 DUT 错误。

## 5. 实现证据

- RTL 评审：
- Lint：
- Directed Regression：
- Random Regression：
- Assertion/覆盖率报告：
- 适用时提供 CDC、DRC 和 Timing 报告：

## 6. 冻结决定

- 接口版本：
- 测试命令和工具版本：
- 结果摘要：
- 已知限制：
- 决定：PASS / FAIL

只有决定为 PASS 且结果已经汇报后，才能开始下一个模块。

