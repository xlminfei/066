# v3.4 正式计算启动记录

本次已按用户授权启动真实研究数据计算。此文件记录启动时状态，不代表全流程已完成。

- 审查提交：c9ec1c58e173dd5209bbbe5e89b2213553fc0630
- 运行副本：C:\Users\minfei\Documents\ChatGPT\建模\runs\v3_4_formal_20260922204324
- 容器名称：ratio-v34-formal-20260922204324
- 容器 ID：2192b83c6d64427cedb3da160125e9f6a4e79c5e123bdc66c7e8e3c5a659981c
- 镜像标签：ratio-analysis-v3-4:formal-20260922204324
- 实际固定镜像 ID：sha256:c67aade078ec1510b1b036a1a34c6ad0aad66534296b9e6587cd9f283093ca58
- 启动时间：2026-09-22 20:48:17 +08:00
- 启动核验时间：2026-09-22 20:48:53 +08:00
- 启动核验：Docker running；CPU 99.61%；首个正式任务 binary / Null / record_equal 已开始，当时正在 C++ / Stan 编译。未据此宣称 MCMC 或诊断完成。

## 前置检查

Docker 构建、环境检查、12 个回归子脚本、真实输入预检均退出 0。32 个源代码、输入及配置文件的 SHA-256 在检查后仍与启动前快照一致。实际计划 256 个拟合任务：16 个全数据拟合、240 个固定五折/十折 CV 拟合。

数据为 input/observations.csv（153 条记录、51 个物种）和 input/sites.csv（365 个物种）。binary 有 50 个物种；joint_bb 有 51 个物种。正式参数未改变：4 链，每链 4000 次迭代、2000 次预热，adapt_delta=0.99，max_treedepth=12。

## 命令与证据

容器执行：

```text
Rscript /project/v34/src/v3_pipeline.R --stage all
```

完整命令、挂载和前置检查回执见 launch_manifest.json、container_created.json、run_prelaunch_checks.ps1 与各 *_exit.json。正式进程由 run_formal.sh 管理，输出同时保存在 Docker 日志和 05_formal_all.log；进程结束后保存 formal_process_exit.json。容器未设置自动删除或自动重启，退出后保留以便核查。

- 运行阶段状态：../v3.4/review/last_stage_status.json
- 正式完成状态：../v3.4/review/final_v3_status.json
- 最终审计：../v3.4/review/audit_v3.json
- 拟合检查点：../v3.4/runs/
- 结果、图及报告：../v3.4/results/、figures/、reports/

代码包自带的 provenance/formal_status.json 是发布时尚未运行的历史记录；本次是否完成应以上述运行阶段状态、进程退出码、诊断及最终审计为准。

按用户要求，在本次初始运行核验后停止持续监控，等待用户在 Docker CPU 归零后通知。CPU 归零后应结合退出码和日志区分正常完成与诊断/其他错误导致的停止。
