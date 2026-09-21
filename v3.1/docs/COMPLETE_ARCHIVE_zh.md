# v3.1 完整说明、中间文件与测试结果

本轮完整交付使用 GitHub 的 v3.1-complete Release。原 v3.1 标签和首次小型ZIP保留为历史，不移动其提交。

## 文件在哪里

- 当前源码、逐项修改说明、图示解释、测试结果及上传收据在仓库 main 的 v3.1/。
- v3.1-complete-evidence.zip 是完整资料快照。working-v3/包含本次原始工作目录的全部现存文件；published-v3.1/包含本次发行目录快照。归档不按后缀或文件大小省略。
- 全部原始fit.rds、早期smoke、pre_v31_audit_snapshot、日志、旧等值图、新差异化夹具、数值后验快照、输入和说明均在相应命名空间内。
- v3.1-complete-evidence.files.csv 列出每个源文件的命名空间、原相对路径、归档路径、字节数和SHA-256。ZIP内另有同一清单和阅读说明。
- 构建收据记录文件数、逐项读回数量、源文件省略数、ZIP字节数和摘要。
- Git提交完整补丁作为独立附件，可核对所有新增/删除代码行及机械性变化；逐函数的原因和测试层级见 CHANGE_DETAILS_zh.md。

## 如何核验

下载ZIP与同名.sha256，在同一目录执行：

~~~bash
sha256sum -c v3.1-complete-evidence.zip.sha256
~~~

也可按.files.csv逐项检查解压后的文件。上传脚本要求GitHub返回的文件大小和服务器SHA-256与本地一致；远端终态收据保存于 provenance/complete_upload_receipt.json。该收据形成之后的索引/提交记录通过Git目录或独立附件提供，不要求归档递归包含它自己。

## 阅读顺序与边界

先读 FIGURE_TEST_EXPLANATION_zh.md，再读 CHANGE_DETAILS_zh.md 和 V3_1_WORKFLOW_zh.md。旧等值图的0.37/0.44/0.51/0.58是人工布局值。新图的大标题明确写SYNTHETIC TEST DATA，数值差异也只是测试数据；Null保持同一训练方式内恒定。

历史失败日志和中间稿会原样保留。它们供追溯，不能与当前终态混为一谈，也不应直接运行其中的旧代码。现有18次真实拟合都是合成测试，正式研究数据的256项拟合仍未启动。

“全部”以两个指定根目录中归档时仍存在的本项目文件及逐文件清单为准。以前已结束容器中的未持久化临时对象无法事后恢复；不以重新编造文件替代原始证据。

早期日志中的“no native compiled binaries in package”及旧清单的“stays local”描述首次轻量Git包；它们作为历史原样保留。本次完整Release另含原始fit.rds，当前范围请以完整归档清单与远端校验收据为准。

## 下载与重组分片

一次上传整个386MB归档时网络连接中断，因此最终附件使用24个分片。它们是同一个已验证ZIP的连续字节切片，不是删减版。每片都单独核验服务器大小与SHA-256。

最方便的方式是下载本版本 scripts/restore_complete_evidence.py（Release也有独立同名附件），在有Python 3的终端执行：

~~~bash
python3 restore_complete_evidence.py --directory v3.1-complete-data
~~~

它会从公开Release下载固定校验清单和24片，逐片校验，再生成 v3.1-complete-evidence.zip 并核对完整SHA-256。Windows使用已安装的Python 3时，可把python3换成python。脚本不覆盖校验不符的已有文件。

已经下载全部分片时，也可以在Ubuntu手动合并：

~~~bash
cat v3.1-complete-evidence.zip.part* > v3.1-complete-evidence.zip
sha256sum -c v3.1-complete-evidence.zip.sha256
~~~

首轮中断的远端starter附件已移除，本地原ZIP和中断日志保留；后续各片只在服务器校验成功后计为完成。上传及重组脚本属于本次快照之后的补充工具，随Git目录与Release独立附件提供。
