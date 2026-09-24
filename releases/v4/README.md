# v4 发布与完整验证资料

> v4现已增加每行中文注释的R交互入口；[最新交互式代码包与验证资料](../v4_interactive/README.md)。本页原v4标签和附件保留其发布时身份。

- [独立代码目录](../../v4/README.md) · [逐项修改](../../v4/CHANGELOG_zh.md)
- [验证报告](../../validation/v4/VALIDATION_zh.md) · [全部验证文件](../../validation/v4/)
- [GitHub v4 Release](https://github.com/xlminfei/066/releases/tag/v4)
- [下载轻量代码 v4-code.zip](https://github.com/xlminfei/066/releases/download/v4/v4-code.zip)：107,989 字节，29个文件，解压后只需v4目录即可在匹配R环境运行。
- [下载完整代码与验证档案](https://github.com/xlminfei/066/releases/download/v4/v4-validation-complete.zip)：81,098,746 字节，384个文件，包括代码、全部测试、中间/失败尝试、两份真实合成拟合RDS、bootstrap对象和图页。

本版本新128项研究数据拟合未启动。固定输入/Stan模型保持原定义；原OOF复算、24个原生对象重放、两次新合成拟合、47项最终守卫检查及128项替身编排均通过。替身与合成结果不称为正式研究拟合。

[归档逐文件清单及SHA256](archive-manifest.json) · [构建读回日志](archive_build.log) · [下载验证脚本](verify_archives.py)

仅下载代码并核验：

~~~bash
python verify_archives.py archive-manifest.json --directory downloads --download --code-only
~~~

下载两份包并逐个验证每个成员：

~~~bash
python verify_archives.py archive-manifest.json --directory downloads --download
~~~

不加--download可核验已有本地包。程序只下载/校验，不执行任何模型。ZIP全文读回和CRC检查已完成；上传收据和公开下载检查另保存在本目录delivery/，避免递归归档。

## 最终交付核验

已发布v4，四个附件大小及服务器SHA256全部通过。匿名下载了完整代码ZIP和完整验证ZIP，分别读回29/384文件，每个成员SHA256和CRC均一致；单独解压代码后，在未挂载旧仓库的环境中准备入口通过。

[最终交付状态](delivery/DELIVERY_STATUS.json) · [公开ZIP全量读回](delivery/public_archive_readback.json) · [公开说明读回](delivery/public_document_readback.json)

便携代码的下载入口是v4-code.zip；GitHub自动生成的Source code ZIP包含整个历史仓库。
