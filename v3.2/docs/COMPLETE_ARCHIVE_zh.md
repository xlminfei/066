# v3.2 完整资料与恢复

发布目标：xlminfei/066仓库，标签v3.2。v3.2/为独立版本；旧v1/v2/v3/v3.1目录和既有标签不改。

普通Git保存本轮全部源码、说明、CSV/JSON数值表、PDF/PNG图、测试入口、日志及逐文件索引。为避免把原生编译/拟合对象反复写入Git历史，.gitignore仅排除v3.2/**/*.rds；这不代表省略交付。**本轮全部RDS和其他现存文件都包含在同一Release的完整归档里**，包括历史失败/中间尝试，归档构建不按文件大小或扩展名排除。

Release提供v3.2-complete-evidence.zip.partNNN分片、parts.json、逐文件files.csv、归档SHA-256、归档构建/逐文件读回收据，以及restore_v3_2_evidence.py恢复工具。下载与校验步骤由releases/v3.2/README.md记录。先按有序分片清单校验每片，再拼接，核对整个ZIP摘要。解压后的_archive/CONTENTS.csv可用于逐文件核对。

归档内只有v3.2/与_archive/元信息。恢复无需运行真实研究。原生RDS针对所记录的Linux/R/rstan环境；若跨平台无法加载，可按对应合成测试脚本重建。不能以重新运行替代此次已上传的原始文件。

完整快照完成后才产生的ZIP/分片清单、上传收据和Git二进制差异附件单独放在Release及releases/v3.2/，不递归塞回ZIP。文件分类清单区分源码、说明、测试证据、历史中间文件和原始RDS；历史PASS或FAILED只代表对应当时检查，不可当作当前正式研究结果。

所有测试图明确标为合成数据；全部正式研究拟合仍未运行。请先读review/VALIDATION_v3_2.md和provenance/formal_status.json，再解释任何测试表或图。
