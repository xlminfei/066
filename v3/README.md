# Ratio analysis v3

This directory is an isolated implementation of the agreed v3 analysis. It does not modify v1 or v2.

The formal grid is four models (`Null`, `M1`, `M2`, `M3`) by two routes (`binary`, `joint_bb`) by two training weightings (`record_equal`, `species_equal`). Every fitted model is evaluated twice from the same unweighted held-out evidence table (`record_equal`, `species_equal`). This produces 16 full-data fits and 240 species-grouped fivefold/tenfold CV fits. Site315 is retained as a predictor inside M1/M2/M3; there is no Site315-only model. Site151 remains in the input and applicability metadata but is excluded from the predictor matrix. Scheme A, phylogeny, and random effects are not part of v3.

The input files are copied from the v2 contract and checked by SHA-256. HIGH/LOW uses `>= 0.5` for point/count observations, `Upper <= 0.5` for LOW intervals, and `Lower >= 0.5` for HIGH intervals. Strictly crossing intervals are excluded from binary scoring but remain in the joint route. M3 keeps panel residue levels with frequency at least four and maps rarer residues to `OTHER`; `MISSING` is separate.

Run from the `v3` directory with an R environment containing `brms`, `rstan`, `posterior`, `digest`, and `jsonlite`. The pipeline stages are `preflight`, `prepare`, `smoke`, `fit`, `cv`, `predict`, and `all`. Formal MCMC is intentionally not launched by the implementation self-check; use `docs/reproduction_ubuntu.md` for an explicit run.

The main modules are `R/data_encoding.R`, `R/weights.R`, `R/fitting.R`, `R/metrics.R`, `R/applicability.R`, `R/cross_validation.R`, and `R/prediction.R`. The Stan likelihood is in `stan/joint_bb.stan`. `src/postprocess_results.R`, `src/plot_species_predictions.R`, and `src/write_reports.R` are read-only post-processing entry points for completed runs. `tests/run_tests.R`, `tests/check_prepared.R`, `tests/check_external.R`, and `tests/check_smoke_scores.R` are deterministic or smoke-interface checks. `renv.lock` and `provenance/runtime_spec.json` record the tested R/package environment, while `provenance/MANIFEST.csv` records hashes for the delivered source, configuration, documentation, and small inputs.

The smoke stage uses 300 iterations and is an interface check. Its low-iteration diagnostic result is deliberately recorded as `PASS_WITH_DIAGNOSTIC_WARNINGS` when the sampler finishes but does not meet formal ESS/R-hat thresholds; it cannot authorize formal results. Formal fits stop on diagnostic failure.
