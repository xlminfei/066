# v3 implementation self-check

This file records checks performed while writing the v3 code. It is not a formal scientific result.

| Check | Result |
|---|---|
| R parsing for every file in `R/`, `src/`, and `tests/` | PASS |
| Contract tests for classification boundaries, encoding, weights, AUC ties, calibration bootstrap, and applicability fields | PASS |
| Prepared-data contract | PASS; 365 panel species, 153 records, 50 binary response species, 51 joint response species |
| Run-plan count | PASS; 16 full-fit tasks, 240 CV-fit tasks, 256 total |
| Docker preflight and source guard | PASS |
| Dockerfile runtime version assertion | PASS; R 4.6.1, brms 2.23.0, rstan 2.32.7, posterior 1.7.0, digest 0.6.39, jsonlite 2.0.0 |
| Low-iteration binary/joint M1 smoke fit and posterior prediction interface | PASS_WITH_DIAGNOSTIC_WARNINGS; no formal ESS/R-hat claim is made |
| Three-species external projection through the frozen encoding and prediction interface | PASS |
| Smoke binary/joint record scoring and weighted ELPD path | PASS |
| GitHub push | Not performed |

The full 16-fit plus 240-CV-fit formal MCMC grid was not started during implementation. Its entry point is `src/v3_pipeline.R --stage all`; formal fits stop on a failed diagnostic gate.
