# v4 发布与完整验证资料

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
