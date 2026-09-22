# v3.3 完整发布与恢复

[版本说明](../../v3.3/README.md) · [修改理由](../../v3.3/docs/CHANGE_DETAILS_v3_3_zh.md) · [测试报告](../../v3.3/review/VALIDATION_v3_3.md)

完整附件发布在本仓库[GitHub v3.3 Release](https://github.com/xlminfei/066/releases/tag/v3.3)。只修复R审计有限尾差精度与比较说明；没有新MCMC或真实研究计算。

完整快照277文件，33个原生RDS（32旧合成fit和1源码相符的编译探针），省略0。ZIP 656142878字节，拆为40片，全部源文件逐项读回通过。

ZIP SHA256: 5fc2b56e7583ad0d8f5ea3a62c788438f39bf9d163c01fb934b932e50981492e

parts.json SHA256: b86dbf4132210f71f3685597e33054174ac724d9fcf9ab80e4c432cee9b56e9e

下载本目录或Release中的restore_v3_3_evidence.py，然后执行：

~~~bash
python restore_v3_3_evidence.py --directory v3.3-complete-data
~~~

脚本下载固定摘要的parts.json，逐片下载并检查大小/SHA256，按清单顺序合并，再核对整个ZIP。已下载且一致的分片可复用；只恢复文件，不运行模型。可加--manifest PATH --no-download对已在本地的完整分片核验。

Git中原生RDS被忽略，它们均在完整ZIP中；本次不以“可以重跑”替代提供文件。源码、说明、CSV/JSON、图件、日志、冻结基线和高精度参考依赖wheel均同时在Git可见。files.csv列出所有源文件，归档内另有_archive/CONTENTS.csv。provenance/ARTIFACT_INDEX.csv为打包前的分类索引，不递归包含自身。

32旧合成fit保留v3.2版本身份、FitKey和FAILED_DIAGNOSTICS状态；本版通过了新版审计复算，没有新增收敛结论。正式16全拟合+240CV仍未执行。

归档之后形成的分片/上传日志/收据/Git补丁独立发布；最终收据加入main而不移动固定v3.3标签。

## 最终交付核验

代码标签v3.3固定在d3a6571d476fc33656b3a998c797b3d552f56da7。Release已发布，57个附件逐个核对GitHub大小与SHA256；额外匿名下载首片、尾片和清单，实际字节全部一致。[最终收据](remote_delivery_verification.json)记录完整附件列表。244个Git版文件与本地字节一致，旧版本改动0，见git_snapshot_validation.json。

发布过程补充ZIP含127个文件，包括全部53项主附件上传日志/收据、恢复检查、执行脚本与Git补丁；4个补充附件使总数为57。补充附件自己的最后上传日志/收据在final_upload_logs/及final_upload_receipts/。

最终匿名API查询受到每IP限额限制（403，remaining=0）；仅元数据查询使用本任务已有授权，Release网页与3个文件样本仍匿名读取成功。原始失败、修正后脚本和通过日志都随本目录保留。详情见public_api_rate_limit_note.md。

所有真实研究计算与新MCMC仍未启动。原32合成短链诊断失败状态未改；这里的完成状态仅针对本次限定修复及资料交付。
