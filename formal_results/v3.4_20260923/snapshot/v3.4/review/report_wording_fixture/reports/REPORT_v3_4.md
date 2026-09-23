SYNTHETIC REPORT CONTRACT TEST ONLY - NO SCIENTIFIC RESULTS
# v3.4 computed analysis report

Version: ratio_analysis_v3_4_weighted_20260922

Purpose: predict a new species from a frozen six-site input table; Site151 is applicability metadata, five other sites enter M1/M2/M3. Models compare joint coding against Null, not causal site effects.

Primary comparison: species-equal evaluation in fivefold species-grouped CV. Tenfold and record-equal evaluation are supplementary. Four combinations reuse two fits, not four independent experiments.

AUC is the equal-fold mean. PooledAUC uses all OOF predictions and is distinct. Log score/MAE/RMSE use weights computed over each metric's complete valid-record set. ELPD is a scaled weighted log-score sum (weight sum=N); MeanLogScore reports the mean on the stated evaluation scale. Compare models or training methods only within the same route, CV design, and evaluation weighting. Different evaluation weightings define different targets; do not rank training methods by comparing their scores across evaluation weightings.

Intervals in model comparisons are conditional species-cluster bootstrap intervals of fixed OOF predictions, excluding refitting and model-selection uncertainty. Approximate P/BH values are exploratory; degenerate or fewer-than-ten-species cases do not receive a P value. Training species may not represent every target species.

The weighted likelihood N/(S R_s) fixes a relative species contribution and overall likelihood scale, not N independent observations or automatic frequentist interval coverage. Do not duplicate records to improve apparent precision.

## All four training/evaluation combinations

| FixtureOnly | Meaning |
|---|---|
| TRUE | synthetic_report_contract_fixture |

## Quantitative point bias and observed-versus-predicted plot

Bias = weighted mean(predicted minus observed), on the same count/exact point subset and weights as MAE/RMSE. Positive means overprediction, negative means underprediction. Interval observations are never imputed as points. Zero mean bias can coexist with large absolute errors.

LogScoreSpeciesUsed/LogScoreRecordsUsed describe the log-score subset; PointSpeciesUsed/PointRecords describe MAE/RMSE/Bias; PISpeciesUsed/PIRecords describe point PI coverage and width. Legacy SpeciesUsed still denotes the log-score set, not all adjacent metrics.

| FixtureOnly | Meaning |
|---|---|
| TRUE | synthetic_report_contract_fixture |

See figures/quantitative_predicted_observed.pdf and results/quantitative_plot_source.csv. Plotted markers are individual count/exact reports; marker area represents evaluation weight; the diagonal indicates equality.

## Models versus Null

| FixtureOnly | Meaning |
|---|---|
| TRUE | synthetic_report_contract_fixture |

## Training methods (species minus record)

| FixtureOnly | Meaning |
|---|---|
| TRUE | synthetic_report_contract_fixture |

## Posterior predictive checks

Observed and replicated statistics use the same record subset, observation type and evaluation weights. count simulations use each observed Total; exact reports use the one-inflated Beta. Interval records are not imputed as points. PPC uses training data and is not independent validation.

| FixtureOnly | Meaning |
|---|---|
| TRUE | synthetic_report_contract_fixture |

Full-panel Point is the posterior mean; CrI describes uncertainty in the expected quantity. Joint full-panel PI describes a future exact-type report without a specified denominator. CV count PI uses the observed denominator; interval overlap is descriptive and is not point coverage.
