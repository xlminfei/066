# F06 分页图标签错配修正记录

复核发现，第一次生成的 v2 F06 分页图存在绘图层面的行映射错误：物种点值行使用了反向 y 位置，而 y 轴标签也以另一种顺序反向排列，导致标签可能显示在另一个物种的点值旁边。这个错误不在模型拟合、High/Low 编码或预测 CSV 中。

同时，旧版分页 source CSV 使用 `match(Species, rows$Species)`，在每页包含多个模型时只保留了第一个模型的行。该 source CSV 也不能作为完整图源。

修正版使用统一的物种顺序和反向 y 轴；每页 source CSV 现在包含 42 个物种 × 5 个模型 = 210 行。修正版文件使用 `_corrected` 后缀：

- `figures/F06_full_species_predictions_binary_corrected.pdf`
- `figures/F06_full_species_predictions_joint_bb_corrected.pdf`
- `figures/F06_full_species_predictions_schemeA_tobit_corrected.pdf`
- `figures/F06_species_*_corrected_p01` 到 `p09`

对两个争议物种的修正版 High/Low 行是：

```text
Cirrhinus molitorella: Null 0.7595; Site315 0.4903; M1 0.2440; M2 0.2518; M3 0.2166
Danio rerio:           Null 0.7595; Site315 0.4903; M1 0.2440; M2 0.3342; M3 0.2777
```

其中 M1/M2/M3 的点预测仍低于 0.5；Null 的 0.7595 才是高于 0.5 的基线预测。旧版未加 `_corrected` 的 F06 图在打包时不得使用。
