# v3.3 runtime

R4.6.1 and79 locked non-base R packages remain identical to v3.2. Dockerfile keeps the exact base-image digest and changes only the version installation path and lockfile environment variable. The successful v3.3 build is recorded in review/environment_build_v33.log; the apt layer was reused, while pinned renv/jsonlite restoration and all79 dependency/version checks executed. This is not a claim of rebuilding every OS package from an empty cache.

review/environment_test_v33.log records rejection of an altered R-version lock and a lock missing BH, plus pinned abind restoration in a clean temporary library. No model fitting occurs in these tests.

The initial Beta function tests used the existing validated v3.2 image with exactly the same R/package versions. Final regression and standalone saved-fit re-audit ran in the newly built v3.3 image. Exact IDs and source hashes are in provenance/runtime_spec.json.

The independent100-digit Python oracle loads a local mpmath1.3.0 wheel from review/reference_dependency. Its SHA256 is checked before import. A pip TLS attempt failed; the verified PyPI release wheel was then fetched normally without disabling certificate checks. No global Python installation was changed.

From the repository root, build with docker build -t ratio-analysis-v3-3:local ./v3.3. Reproduction commands are in docs/reproduction_ubuntu.md.
