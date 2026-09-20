# v3.1 environment restoration

The validated environment uses R 4.6.1 and a complete lock of 79 non-base R packages, including the recursive `Depends`, `Imports`, and `LinkingTo` dependencies of `brms`, `rstan`, `posterior`, `digest`, `jsonlite`, and `renv`. Optional `Suggests` packages are not universally installed. The tested versions, exact base-image digest, local image ID, and file hashes are recorded in `provenance/runtime_spec.json`.

Build from this version directory (the directory containing `Dockerfile` and `renv.lock`):

```bash
docker build --progress=plain -t ratio-analysis-v3-1:local .
docker run --rm \
  --mount type=bind,source="$PWD",target=/project/v3,readonly \
  --workdir /project/v3 \
  ratio-analysis-v3-1:local \
  Rscript scripts/test_environment.R
```

The Dockerfile fixes the base-image digest. It first obtains r2u binary packages for speed, then runs `scripts/restore_environment.R` to restore any missing or mismatching R versions from the lock. The script bootstraps exactly renv 1.2.4 and verifies its source archive with SHA-256 before installation. It then verifies the exact R version, all 79 package versions, dependency closure, and actual model namespace loading. A mismatch fails the build. It does not start model fitting.

The environment tests also require rejection of an altered R-version lock and a lock missing the transitive `BH` dependency. They exercise source restoration of `abind` into a clean temporary library. The successful Docker build additionally restored `jsonlite` from source. Tests only use temporary files and libraries inside the container; the package mount remains read-only.

For a prepared Ubuntu host that already has R 4.6.1, compilers, and the required system libraries, an explicit restoration is also available:

```bash
export R_LIBS_USER="$HOME/R/ratio-v3-1"
mkdir -p "$R_LIBS_USER"
Rscript scripts/restore_environment.R --library "$R_LIBS_USER"
```

Keep `R_LIBS_USER` set when running subsequent analysis commands on that host. The tested reproducibility path is the Docker build. Additional Ubuntu system packages come from apt repositories, so future OS-layer bytes may differ even though the base digest and complete required R package versions are checked. Repository/network availability is required for a new build. Unavailable pinned artifacts cause a failure, not an unannounced package upgrade.

`review/environment_build.log` preserves the build attempts and final successful build/test exit codes. An initial attempt was stopped after a version-string normalization error was identified; another reached all dependency checks but failed at final R-version log formatting. Both defects were corrected before the successful build. These environment results do not substitute for the pipeline's separate regression, Stan-interface, or formal-fit diagnostics.
