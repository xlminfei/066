# v4 交互式入口独立复核

复核范围为 `v4/interactive_analysis.R`、`v4/interactive_support.R` 及其与原 v4 准备、缓存、诊断和完成检查的调用关系。两项确认的问题已修复，当前支持层回归检查 **17/17 通过**；本次复核未发现仍需修复的问题。

相对于基线 `7ce962e`，`v4/R`、设置、四阶段、`run_all.R`、Stan 和冻结 CSV 没有差异。本次审查没有改动生产源文件、Git 状态或远端内容。

## 已确认并修复的问题

1. **二分类公式的实际权重没有绑定到示例规格。** 初始示例检查比较了 request、key、data、blueprint、code 和 prior，却没有核对公式求值后的数据。无采样复现表明，把公式中的 `weights(TrainWeight, scale = FALSE)` 改为 `weights(TrainWeight * 2, scale = FALSE)` 后，生成的 Stan 代码仍完全相同，但 `make_standata()` 中的训练权重从全 1 变成全 2，原检查仍接受该规格。修复后，示例检查重新生成实际 Stan 代码和 standata，并与冻结规则重建的规格严格比较。两次独立重建得到的 standata 可以直接使用 `identical()`，无需忽略属性。当前回归检查已确认：正常规格通过，权重表达式变更在拟合前失败。

2. **函数加载后、准备数据前修改源码，可能把旧内存函数记为新磁盘来源。** 初始流程在准备时计算磁盘源码身份，但后续重建仍调用先前加载的函数。容器临时副本中的复现证明，磁盘上的编码函数已改成直接报错后，旧内存函数仍能准备和恢复状态，并把新磁盘哈希写入 prepared。修复后，核心加载与身份捕获组成同一表达式，`interactive_begin()` 把核心、支持文件和主文件身份绑定到当前会话，每个计算块及设置恢复前都检查这些身份。当前检查确认：准备前的核心源码变化、会话中的支持文件变化和主文件变化均在表达式执行前被拒绝。

## 已执行的支持层检查

- 调用者环境中的赋值可以继续在控制台使用；表达式执行前状态已是 `RUNNING`。
- 标准输出、R 消息和警告被写入日志；重复步骤追加日志。
- 错误停止后续语句并保存 `FAILED`；模拟中断保存 `INTERRUPTED`。
- 已有 output sink 被保留；正常、错误和中断退出后没有新增连接或 sink 泄漏。
- 从磁盘恢复设置后，临时修改的采样参数和稀有阈值复原，准备状态保持一致。
- 合法示例规格通过；改变实际权重的公式和错配折号被拒绝。
- 没有完整拟合产物时，`interactive_finish()` 拒绝完成并保存失败状态。
- 两份交互文件的每个非空代码行都有中文注释。
- 三类会话中源码变化均在使用旧函数执行后续表达式之前失败。

测试脚本为 `review_checks/test_support.R`；逐项结果、来源哈希和控制台日志分别保存在 `review_checks/support_checks.csv`、`review_checks/support_status.json` 和 `review_checks/support_test.log`。

## 执行边界与来源

测试使用固定镜像 `sha256:c67aade078ec1510b1b036a1a34c6ad0aad66534296b9e6587cd9f283093ca58`。仓库挂载为只读，只有 `validation/v4_interactive/review_checks/` 作为证据输出可写；所有准备状态、修改后的源码副本和故障示例位于容器临时目录。

已测试核心 `analysis_id`：`75ac77db4f6fa772a7c6a4038b5b70ba93b8b8b103add1b38fe71f11319f2b7a`。

已测试交互文件 SHA256：

- `interactive_analysis.R`：`95b2f82b3a85409198c70055b4af6400824439d1eeb2bcf8e05e3e2355a3b9eb`
- `interactive_support.R`：`cd4507f6718bef0e43321b1a93df006d8c6a98a29112a6ebfddbf72f2e8d9976`

没有执行新的 MCMC、模型编译或批量拟合阶段。测试只生成模型规格和 Stan 输入，未调用 `fit_from_spec()` 或 `fit_stage()`。全主文件在干净会话中的逐表达式重放、现存原生缓存的实际读取及完整流程正向完成，由主代理另行验证；本次 17 项支持层检查不替代这些证据。
