# v3.2 完整交付

仓库版本目录：[v3.2](../../v3.2/README.md)。完整资料在本仓库[GitHub v3.2 Release](https://github.com/xlminfei/066/releases/tag/v3.2)。

本轮审查3.1—3.5与7.3的修改、必要的M1/M2模板缓存修复及测试已纳入版本。7.1/7.2未增加；真实研究数据计算未启动。

## 内容与校验

- 源目录完整快照：280个文件，47个原生RDS，逐文件读回核验通过，省略0文件。
- ZIP：1007573820字节，拆成61片；所有分片按parts.json顺序拼接恢复同一个ZIP。
- ZIP SHA-256：51a577666046b0d667534485df6626a61bd59c35f589b46d7e0ddb553ce83c56
- parts.json SHA-256：f0bd5d1c325dfb7000fce7ee45820e786b3ae4b5ca6e378fd9e827afda7eef29
- 全部源路径、字节数与SHA-256：[files.csv](v3.2-complete-evidence.files.csv)。归档内另有_archive/CONTENTS.csv；provenance/ARTIFACT_INDEX.csv是打包前分类索引，本身不递归列入自身。
- 本地打包/逐文件读回收据：[build.json](v3.2-complete-evidence.build.json)。上传完毕后的GitHub服务器摘要/大小收据另行加入本目录及Release。

## 下载与恢复

下载本目录或Release附件中的restore_v3_2_evidence.py，在新目录运行：

~~~bash
python restore_v3_2_evidence.py --directory v3.2-complete-data
~~~

脚本固定本发布的清单与归档摘要，下载并校验每片，按顺序合并ZIP；已下载且摘要一致的分片可复用。它拒绝错误文件名、缺片和摘要不符，不会开始模型计算。解压ZIP即可取得全部v3.2源码、说明、测试结果、中间记录和原始拟合对象。

已下载全部分片时，可用--manifest PATH_TO_PARTS_JSON --no-download校验并合并。Git普通目录省略的仅为原生RDS，它们均已在完整ZIP中；不是要求用户重跑代替提供原始文件。

## 结果解释

32项最终真实合成拟合完成的是接口和后验复算验收；32项短链全部未通过正式诊断阈值，原始诊断表完整保留。复算覆盖1472行OOF及192行合成面板，最大绝对差8.4377e-15。正式16全拟合+240CV仍为NOT_RUN_BY_USER_INSTRUCTION。

快照后的分片清单、恢复脚本、上传收据和Git二进制补丁独立交付，避免归档递归包含自身。v3.2标签固定代码/测试快照；上传收据可通过后续main提交补充，版本代码不因此改变。

## 最终交付验收

[公开交付收据](remote_delivery_verification.json)：Release已发布，80个附件逐个核对GitHub大小/SHA-256；额外匿名下载首片、尾片和清单，实际字节摘要全部一致。233个Git版本文件与本地字节一致，旧版本改动0，见[Git快照核验](git_snapshot_validation.json)。

执行证据补充ZIP包含168个归档/恢复/上传过程文件，包含全部73项主附件上传日志与收据；7个补充附件使最终总数为80。补充ZIP本地逐文件读回通过，目录和摘要见v3.2-delivery-execution-evidence.files.csv及build.json。

发布时按标签读取草稿返回404，改用已确认Release ID完成发布；.NET匿名下载检查等待过长，停止后改用Node匿名获取公开清单并下载字节，全部通过。这些过程及脚本作为独立后续证据保留，不更改固定v3.2源代码标签和完整归档。

归档内figures/pdfinfo.txt保留的是方形坐标修整前的中间检查；当前最终PDF为4页，实际大小/SHA和元信息见figure_metadata_final.json及txt。图片数值不因该版式修整改变。

如需重跑最终新增定量文件交叉核验，在完成两个合成测试后执行tests/test_quantitative_artifacts.R。恢复脚本会对每片及ZIP校验；此次已下载部分的本地复核日志见restore_local_validation.log。
