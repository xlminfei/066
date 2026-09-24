# v4 core review and publication-guard regression evidence

The three previously reported core findings are resolved in the reviewed source. The bounded follow-up suite passed **47 of 47 checks**. No new actionable issue was found in this follow-up review.

The original review also confirmed byte-identical v3.4/v4 joint Stan sources and source-level preservation of the record-equal training targets, priors, full/CV seed rules, prediction targets and applicability definitions. That inspection is not a claim that the 128 formal v4 fits have run.

| Finding | Reviewed correction | Executed evidence |
| --- | --- | --- |
| Prepared contents could differ from frozen CSVs while retaining their identity labels. | `load_prepared()` rebuilds the state through `read_frozen_state()` and compares every derived component. | Fresh and restored states load; modified observation and encoding values fail; a structurally valid but different joint fold assignment also fails. |
| Completion trusted self-declared receipt lists and only counted metric rows; fit files could be absent. | Canonical stage file sets, required schemas/exact keys and a 128-file fit manifest are checked. The completion gate also recomputes BH3. | Canonical receipt round trips pass; empty/incomplete/duplicate lists, malformed stored receipts and changed/missing files fail. Duplicate or wrong metric identities fail. The previous false-COMPLETE fixture fails. A correctly shaped manifest referring to absent fit files fails. |
| Prediction validation accepted keys without numeric prediction columns. | Required prediction columns and configured grid identities are checked before interval validation. | Valid binary/joint prediction rows pass; each omitted prediction column, a keys-only table and an unknown model fail. |

Test script: `validation/v4/test_publication_guards.R`.

Initial evidence: `validation/v4/guard_checks/checks.csv`, `status.json`, and `test.log`.

After the final `04_plot.R` label-spacing and BH-caption adjustments, the unchanged guard suite was rerun once into the fresh `validation/v4/guard_final/` directory. All **47 of 47 checks passed** again. Its `checks.csv`, `status.json`, and `test.log` record the final tested analysis identity `75ac77db4f6fa772a7c6a4038b5b70ba93b8b8b103add1b38fe71f11319f2b7a`. The source review was not repeated for unchanged functions.

Execution used R 4.6.1 in Docker image `sha256:c67aade078ec1510b1b036a1a34c6ad0aad66534296b9e6587cd9f283093ca58`. The repository was mounted read-only at `/project`; only `validation/v4/guard_checks/` was mounted writable as `/guard-results`. All malformed fixtures were created in the container's temporary directory. Persistent source changes by this reviewer are limited to this review and the regression script.

Command inside that container:

```text
Rscript /project/validation/v4/test_publication_guards.R /project /guard-results
```

The initial tested analysis identity was `d21a2caef3c987cf5be042fa05b7e1886e0a4a4750c317749c59a6cd900bd1d4`; the final tested identity is recorded above. The frozen input file hashes were unchanged in both runs. No model compilation, MCMC, real-data fitting, source editing, Git mutation or external operation was performed by the tests.

The suite deliberately does not establish positive full completion of 128 genuine fits, full sampler/cache correctness or complete statistical equivalence. Those require the separate model, saved-posterior and orchestration checks coordinated by the main reviewer. The previous false-COMPLETE reproduction now fails at its first missing required diagnostic field; the independent absent-fit test reaches and verifies the new file-inventory gate without creating any fit file.
