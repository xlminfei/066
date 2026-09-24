# Ubuntu 手动复核

只复制 v4 目录，或下载 v4-code.zip 解压。不需要带入旧版本目录、历史测试、11GB旧拟合归档或本次验证目录。

## 环境

原验证环境为 Ubuntu 24.04、R 4.6.1；R包版本在 renv.lock，包含79个锁定包。已有相同环境时可直接运行，无需Docker。

在 R 4.6.1 和相应系统编译库已准备的服务器上，可以运行一次：

~~~bash
Rscript environment/restore.R --library /your/path/R-library
~~~

该脚本验证R版本、固定renv引导源码SHA、依赖版本和命名空间。随后让R使用该目录：

~~~bash
export R_LIBS_USER=/your/path/R-library
~~~

这不是环境升级脚本。不要在此次复核同时升级建模包或修改先验。环境恢复可能需要网络和系统库安装；真正分析不需要联网。

Docker是可选路径：

~~~bash
docker build -t ratio-analysis-v4 .
docker run --rm --mount type=bind,source="$PWD",target=/project/v4 -w /project/v4 ratio-analysis-v4 Rscript 01_prepare.R
docker run --rm --mount type=bind,source="$PWD",target=/project/v4 -w /project/v4 ratio-analysis-v4 Rscript 02_fit.R > output/fit.log 2>&1
docker run --rm --mount type=bind,source="$PWD",target=/project/v4 -w /project/v4 ratio-analysis-v4 Rscript 03_evaluate.R > output/evaluate.log 2>&1
docker run --rm --mount type=bind,source="$PWD",target=/project/v4 -w /project/v4 ratio-analysis-v4 Rscript 04_plot.R
~~~

每次检查命令退出码为0后再执行下一步。Dockerfile按原基础镜像与锁文件恢复依赖，工作目录只挂载本v4目录。

## 四阶段复核

1. 01_prepare.R：检查 analysis_manifest.json 的支持数、run_plan.csv 的128项、panel_encoded.csv 的分类；只准备，不拟合。
2. 02_fit.R：实际从输入执行8全数据＋120CV拟合；全过程日志自行重定向保存。fit_diagnostics.csv 每项完成后立即更新，停止时查看最后一项错误。相同身份缓存可续跑。
3. 03_evaluate.R：计算物种等权指标、50000/2000次bootstrap和三项BH。核对16行汇总、30行检验、10个FamilyID，每组FamilySize=3。
4. 04_plot.R：绘制7份PDF，并做最终文件、主键和128拟合对象完整性检查。查看 status.json 是否 COMPLETE 或 COMPLETE_WITH_REVIEW_FLAGS；后者还需阅读PPC摘要。

运行时间取决于服务器；128项拟合不能以一次小型测试代替。当前验证证明代码与既有定义的对应和所测接口，不代表已经替你完成新v4全量正式复核。重新MCMC可能存在正常浮点和Monte Carlo差异，应核对模型、输入、折表、设置和诊断，不要求新抽样每个小数位逐位相同。
