# v1 输入文件

`observations.csv`、`sites.csv` 和 `tree.nwk` 是 v1 的完整输入。`tree.nwk` 是 P 结构所需的物种树；v2 不读取它。六个位点的提取依据、记录字段、High/Low 边界和 interval 规则见 `docs/输入文件格式.md` 与 `docs/01_输入与编码.md`。

v1 运行前应核对文件 SHA256，并使用新的运行标签；不要把 v2 的 `Site151` 排除规则或 v2 结果表混入 v1 的历史复现。

