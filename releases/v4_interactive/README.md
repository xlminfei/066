# v4交互式入口下载

本次仍是v4代码，新增每行中文注释的R交互入口。原v4标签和附件保留；本更新用v4-interactive标签保存独立快照。

- [完整逐行代码](../../v4/interactive_analysis.R) · [Ubuntu R操作/恢复说明](../../v4/INTERACTIVE_zh.md)
- [下载独立代码包](https://github.com/xlminfei/066/releases/download/v4-interactive/v4-interactive-code.zip)：124,951字节，32个文件；运行只需这个代码包。
- [GitHub发布页及完整验证分卷](https://github.com/xlminfei/066/releases/tag/v4-interactive)
- [逐项修改与理由](../../validation/v4_interactive/CHANGE_DETAILS_zh.md) · [完整验证](../../validation/v4_interactive/VALIDATION_zh.md)

完整验证ZIP为160,824,760字节，771个文件，分成5卷，全部保存原生缓存、中间表、bootstrap对象、日志和失败/成功尝试。分卷只用于完整开发档案，独立代码包不需要合并。

[清单与SHA256](archive-manifest.json) · [下载合并校验程序](verify_archives.py) · [构建读回日志](archive_build.log)

~~~bash
python verify_archives.py archive-manifest.json --directory downloads --download --code-only # 只下载并核验独立代码包。
python verify_archives.py archive-manifest.json --directory downloads --download # 下载代码及5个验证分卷、合并并逐个核验所有ZIP成员。
~~~

本次没有任何新MCMC；验证使用既有原生缓存和明确的批量替身。普通R会话不提供--file参数，实际顺序执行110个主文件表达式。145/145主代码行和97/97支持代码行均有中文注释。

## 最终交付

八个发布附件已核对服务器大小/SHA256。匿名实际下载代码包和全部五个分卷，合并后读回完整771文件；代码包32文件也逐项通过SHA256和CRC检查。四份公开源代码/说明原文已读回核验。

[交付状态](delivery/DELIVERY_STATUS.json) · [公开下载及合并读回](delivery/public_archive_readback.json) · [独立代码包在普通R中的前80个表达式](delivery/portable_check/portable_status.json)

打包后的发布/独立包检查属于交付记录，保留在delivery/，没有递归放回被核验的ZIP。
