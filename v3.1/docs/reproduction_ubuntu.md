# v3.1 Ubuntu / Docker 复现

从仓库根目录运行。原 v1、v2、v3 保留，本版目录为 v3.1。

~~~bash
# 构建上下文必须是版本目录，不能用仓库根目录代替。
docker build --progress=plain -t ratio-analysis-v3-1:local ./v3.1

# 不启动正式拟合的检查；入口根据脚本路径自动定位根目录。
docker run --rm --mount type=bind,source="$PWD",target=/project \
  ratio-analysis-v3-1:local Rscript /project/v3.1/tests/run_tests.R

docker run --rm --mount type=bind,source="$PWD",target=/project \
  ratio-analysis-v3-1:local Rscript /project/v3.1/src/v3_pipeline.R --stage preflight

docker run --rm --mount type=bind,source="$PWD",target=/project \
  ratio-analysis-v3-1:local Rscript /project/v3.1/tests/test_orchestration.R

# 合成数据上的16次真实拟合，用于接口验收，不是研究结果。
docker run --rm --mount type=bind,source="$PWD",target=/project \
  ratio-analysis-v3-1:local Rscript /project/v3.1/tests/test_integration.R
~~~

用户决定启动正式计算时，再执行下面的命令。本次代码发布没有执行它。

~~~bash
docker run --rm --mount type=bind,source="$PWD",target=/project \
  ratio-analysis-v3-1:local Rscript /project/v3.1/src/v3_pipeline.R --stage all
~~~

正式全数据拟合完成并通过诊断后，可外部预测与导出便携包：

~~~bash
docker run --rm --mount type=bind,source="$PWD",target=/project \
  ratio-analysis-v3-1:local Rscript /project/v3.1/src/v3_pipeline.R \
  --stage external --new-data /project/new_species_sites.csv \
  --out /project/v3.1/results/external_predictions.csv

docker run --rm --mount type=bind,source="$PWD",target=/project \
  ratio-analysis-v3-1:local Rscript /project/v3.1/src/v3_pipeline.R \
  --stage export --out /project/v3.1/exports/model_package.rds
~~~

参数入口为 config/analysis.json。旧的 --iter/--warmup/--chains/--cores/--seed/--config 覆盖参数已明确拒绝，避免出现“改了参数却未生效”。模型网格、五/十折、预测位点和归一化规则为冻结合同，越界修改会报错。输入或配置变更后先重新 preflight；旧缓存只有当前请求身份和实际拟合对象都通过验证时才复用。

首次构建需联网获取锁定依赖。基础镜像摘要完整固定，79个必需R包按完整renv.lock恢复并校验；附加apt系统包未采用历史快照，因此不保证未来镜像逐字节相同。构建失败不会被当成依赖已恢复。详见 scripts/ENVIRONMENT.md 和 review/environment_build.log。
