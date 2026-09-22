# v3.4 完整交付

[版本说明](../../v3.4/README.md) · [修改明细](../../v3.4/docs/CHANGE_DETAILS_v3_4_zh.md) · [测试报告](../../v3.4/review/VALIDATION_v3_4.md)

本仓库[GitHub v3.4 Release](https://github.com/xlminfei/066/releases/tag/v3.4)提供单个完整ZIP。此次没有新的RDS或MCMC，全部221个版本文件既进入Git，也进入归档；没有按大小或扩展名省略。

ZIP文件：v3.4-complete-evidence.zip，619833字节。

SHA256：abb1db9af70d5bc53b7c958cb599acef85f038344137162767090de4908cf5db

逐文件清单见files.csv，归档内另有_archive/CONTENTS.csv；本地打包后全部221文件逐个读回核验通过。分类ARTIFACT_INDEX.csv不递归列入其自身。

## 下载与核验

下载本目录或Release中的verify_v3_4_archive.py后运行：

~~~bash
python verify_v3_4_archive.py --directory v3.4-complete-data
~~~

它下载ZIP，检查固定大小/总SHA，逐项检查221个源文件大小/SHA及ZIP完整性。不会自动解压或运行分析。也可在GitHub直接下载ZIP，再执行：

~~~bash
python verify_v3_4_archive.py --archive PATH_TO_ZIP
~~~

校验通过后手动解压即可取得全部源码、说明、基线、合成测试输入/结果、中间轮次和日志。过去各版原生拟合对象保留在对应旧Release，本轮只复用实际需要的合成OOF CSV，来源与SHA已注明。

## 验收边界

151项防护检查通过；640组合法输入指标与旧版逐字段完全一致，默认折表不变。240任务是合成替身编排，未进行真实拟合。原32项短链诊断状态没有变更；正式256项研究拟合未运行。

完整Git补丁与打包后才产生的交付过程/上传收据另行提供，避免ZIP递归包含自身。固定v3.4标签保存代码快照，最终上传收据可通过后续main提交补充。
