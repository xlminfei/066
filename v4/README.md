# v4：记录等权训练 × 物种等权评价

这是可以单独复制到 Ubuntu 运行的发表用代码。只运行一种训练—评价组合，包含 binary（High/Low）和 joint_bb（比例）两条路线，每条路线包含 Null、M1、M2、M3。五折和十折使用随包保存的物种折表，各执行一次完整交叉验证。

本次交付是代码重构与验证。v4 的 128 项研究数据拟合尚未启动；已保存预测的复算、合成数据拟合和调度测试分别记录在仓库 validation/v4，不能把它们称为新的正式研究运行。

## 四步运行

在本目录工作，先准备与 renv.lock 一致的 R 4.6.1 环境，然后执行：

~~~bash
Rscript 01_prepare.R
Rscript 02_fit.R > output/fit.log 2>&1
Rscript 03_evaluate.R > output/evaluate.log 2>&1
Rscript 04_plot.R
~~~

每一步成功退出后再执行下一步。也可以一次运行全部步骤：

~~~bash
Rscript run_all.R > output/run.log 2>&1
~~~

output 目录随包提供。所有入口均允许唯一的可选参数 --output DIRECTORY，例如：

~~~bash
Rscript run_all.R --output /data/my_v4_run
~~~

重跑拟合阶段时，只有训练数据、编码、模型、先验、软件、采样参数及种子身份一致、原生载荷校验通过的缓存才会被复用。诊断不通过会立即停止，并保存诊断和 status.json。若修改程序或 settings.R，请选择新的输出目录；不要把不同分析身份混入已有结果。

## 主要文件

| 文件 | 内容 |
|---|---|
| settings.R | 唯一参数入口：模型、路线、权重口径、正式采样、种子、bootstrap 次数、冻结输入身份 |
| 01_prepare.R | 读取六张 CSV，保留三种观测类型，构建冻结编码，检查四张物种折表 |
| 02_fit.R | 8 个全数据模型＋120 个 CV 模型；预测、PPC、逐项诊断与缓存 |
| 03_evaluate.R | 物种等权指标、30 项检验和每组三项 BH；保存完整 bootstrap 中间对象 |
| 04_plot.R | ROC、校准、ELPD/误差指标、差值检验、预测—观测及 365 物种预测图 |
| R/ | 六个底层模块：加载、检查、编码、模型、指标和绘图 |
| stan/joint_bb.stan | 原经过验证的稳定似然计算；与 v3.4 字节一致 |
| data/ | observations.csv、sites.csv 和四张冻结物种折表 |
| renv.lock | 原 R 依赖版本，未随重构升级 |

[方法与检验解释](METHODS_zh.md) · [输入、输出和验收数量](INPUT_OUTPUT_zh.md) · [Ubuntu 环境与分步复现](UBUNTU_zh.md)

## 检验与 BH 校正

分类路线检验 AUC 对 0.5，以及 MeanLogScore/ELPD 对同训练方式的 Null；定量路线分别检验 MeanLogScore/ELPD、MAE、RMSE 对 Null。ELPD 与 MeanLogScore 在同一评价集合内只差尺度，表中只设置一次 MeanLogScore 检验。

每个 Route × Metric × Design × TrainWeighting × EvalWeighting 家族恰有 M1/M2/M3 三行，P_BH3 使用 BH、固定 n=3。共 30 行、10 个家族。Null 保留在描述指标中，不进入这三项检验。缺少一个模型会报错；不可估计的 P 保留 NA，家族规模仍为 3。

本版本是在开发比较后确定的单组合分析。三项 BH 是本版本明确采用的校正方案，并不控制此前所有开发选择。P 值来自固定 OOF 预测上的物种重抽样与双侧正态近似，不包含完整重拟合、分折选择等不确定性。完整说明见 METHODS_zh.md。

## 保留与精简

保留原始数据、M1/M2/M3 位点分类、先验、0/1 端点及区间处理、稳定 Beta 算法、基本输入检查、物种分组、采样诊断、PPC 摘要和适用范围警告。

删除另一种训练及评价分支、训练方式之间的比较、逐折 P 值表、随机分折生成器、多份 JSON 设置、默认重开全部后验的大审计、长自动报告和新物种输入接口。历史版本、开发测试及发布工具不属于这个代码包的运行依赖。

本包不会下载历史拟合对象，也不从旧结果表挑出几行作为新拟合结果；从零运行将实际完成 128 项拟合。验证和发布档案保留在仓库的独立目录：

- [逐项修改和验证](https://github.com/xlminfei/066/tree/main/validation/v4)
- [v4 代码与完整验证档案下载](https://github.com/xlminfei/066/releases/tag/v4)
