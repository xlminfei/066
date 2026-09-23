# v3.4 复验命令

从Git仓库根目录执行，或先把完整ZIP解压为当前目录下的v3.4/。这些命令不进行MCMC或真实研究数据拟合。

~~~bash
docker build --progress=plain -t ratio-analysis-v3-4:local ./v3.4

docker run --rm --mount type=bind,source="$PWD/v3.4",target=/project/v34,readonly \
  ratio-analysis-v3-4:local Rscript /project/v34/scripts/test_environment.R

# before要求在冻结v3.3代码中复现输入漏洞，成功退出标记FAIL_REPRODUCED。
docker run --rm --mount type=bind,source="$PWD/v3.4",target=/project/v34 \
  ratio-analysis-v3-4:local Rscript /project/v34/tests/test_v34_input_guards.R before

# 新防护、原有回归、240任务合成替身、合法结果对照及报告/范围/解析检查。
docker run --rm --mount type=bind,source="$PWD/v3.4",target=/project/v34 \
  ratio-analysis-v3-4:local Rscript /project/v34/tests/run_v34_regressions.R
~~~

每个子脚本独立R进程运行，详细日志和退出码在review/。test_v34_legal_equivalence.R比较旧合成OOF及当前合成替身输出，需要先运行runner中的fullgrid测试；runner已按依赖顺序安排。

本轮没有必要重新加载原生拟合对象或重跑未变的Stan数值测试。未变源码以SHA核对，原测试证据仍保留于v3.3。继承的测试文件只是保留兼容源码，不代表每个都在本轮执行；部分旧测试需旧发布中的fixture/RDS或会启动合成MCMC。只用本页列出的本轮入口可复现本次验收。

正式模型配置仍为4链、4000次迭代/2000预热、adapt_delta=.99、max_treedepth=12，诊断门不变。此次不调用真实资料的all/smoke/fit/cv/predict；--stage all也不自动执行测试套件。
