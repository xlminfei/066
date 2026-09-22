# v3.3 合成/审计复验步骤

从完整Git仓库根目录执行；或将完整归档解压后的v3.3目录放入当前目录。以下命令均不启动研究数据拟合，最后的旧对象复验需要完整Release归档中的RDS。

~~~bash
docker build --progress=plain -t ratio-analysis-v3-3:local ./v3.3

docker run --rm --mount type=bind,source="$PWD/v3.3",target=/project/v33,readonly \
  ratio-analysis-v3-3:local Rscript /project/v33/scripts/test_environment.R

# 原R审计错误的fail-before及修复后定向测试。
docker run --rm --mount type=bind,source="$PWD/v3.3",target=/project/v33 \
  ratio-analysis-v3-3:local Rscript /project/v33/tests/test_audit_beta_reference.R before
docker run --rm --mount type=bind,source="$PWD/v3.3",target=/project/v33 \
  ratio-analysis-v3-3:local Rscript /project/v33/tests/test_audit_beta_reference.R after

# 312组相同参数上的Stan/R审计/100位参考比较。
docker run --rm --mount type=bind,source="$PWD/v3.3",target=/project/v33 \
  ratio-analysis-v3-3:local Rscript /project/v33/tests/build_audit_beta_cases.R
python3 v3.3/tests/high_precision_audit_reference.py
docker run --rm --mount type=bind,source="$PWD/v3.3",target=/project/v33 \
  ratio-analysis-v3-3:local Rscript /project/v33/tests/test_audit_beta_three_way.R

# 全部本轮确定性/替身/报告/范围回归。
docker run --rm --mount type=bind,source="$PWD/v3.3",target=/project/v33 \
  ratio-analysis-v3-3:local Rscript /project/v33/tests/run_v33_regressions.R

# 对已保存32个真实合成fit做身份核验与新版审计，不重新采样。
docker run --rm --mount type=bind,source="$PWD/v3.3",target=/project/v33 \
  ratio-analysis-v3-3:local Rscript /project/v33/tests/test_v33_reaudit_saved_fits.R
~~~

before按要求重现旧版错误时成功退出，标为FAIL_REPRODUCED；这不是新版失败。三方测试复用functions源码逐行一致且哈希记录的Stan编译对象，只调用Fixed_param/log_prob接口。Python用zipimport直接读取本地已校验mpmath wheel，不需要联网安装。预生成100位参考表也随归档保存。

原有测试文件按兼容性保留；例如test_unequal_integration.R会进行合成MCMC，但本轮未运行。不要把未运行的旧测试当作本轮证据。实际执行清单在review/regression_runner.csv及VALIDATION_v3_3.md。

正式运行的入口仍为src/v3_pipeline.R；本轮不执行--stage all、真实数据smoke/fit/cv/predict。32个原短链对象保持v3.2身份和FAILED_DIAGNOSTICS，v3.3正式缓存和正式诊断门均拒绝它们；不能改版本号或关掉门槛充当正式结果。
