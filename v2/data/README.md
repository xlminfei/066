# v2 输入文件

`observations.csv` 是实验记录；`sites.csv` 是固定的 365 物种、六个位点残基表；`contract.json` 是输入字段、版本和哈希合同。Site151 必须保留在 `sites.csv`，但 v2 训练设计只使用 Site3、Site20、Site117、Site196、Site315。

`contract_previous_site151_included.json` 是被 v2 替代的旧合同，仅用于追踪 Site151 从旧版输入口径转为“保留输入、排除预测变量”的过程；正式运行使用 `contract.json`。

新物种预测也必须提供同样的六个位点字段。位点字符应来自同一条参考多重比对中以 `Siniperca_chuatsi` 去掉 gap 后的编号；程序不会重新比对或重新定义位点。
