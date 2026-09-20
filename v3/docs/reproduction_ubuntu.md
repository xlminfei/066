# Ubuntu/Docker reproduction

From the repository root:

```bash
docker build -f work/ratio_analysis_20260914_v3/Dockerfile -t ratio-analysis-v3 .
docker run --rm \
  --mount type=bind,source="$PWD",target=/project \
  --workdir /project \
  ratio-analysis-v3 \
  Rscript work/ratio_analysis_20260914_v3/tests/run_tests.R

docker run --rm \
  --mount type=bind,source="$PWD",target=/project \
  --workdir /project \
  ratio-analysis-v3 \
  Rscript work/ratio_analysis_20260914_v3/src/v3_pipeline.R \
  --stage preflight --root /project/work/ratio_analysis_20260914_v3

docker run --rm \
  --mount type=bind,source="$PWD",target=/project \
  --workdir /project \
  ratio-analysis-v3 \
  Rscript work/ratio_analysis_20260914_v3/src/v3_pipeline.R \
  --stage all --root /project/work/ratio_analysis_20260914_v3
```

The run creates a new `runs/` and `results/` tree below v3. It does not read v1/v2 RDS files. The fit cache identity includes the input hashes, design blueprint, Stan source, priors, sampling settings, seed, train weighting, and exact training rows. Evaluation weighting is applied only after the record-level held-out evidence table is created, so changing evaluation weighting does not refit a model.
