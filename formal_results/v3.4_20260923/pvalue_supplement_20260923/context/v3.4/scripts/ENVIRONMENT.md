# v3.4 runtime

The Dockerfile retains the pinned rocker/r2u base digest and unchanged renv.lock (R4.6.1;79 non-base packages). Only its version-specific installation path and lockfile environment name change. The new image build and environment tests are recorded in review/environment_build_v34.log and review/environment_test_v34.log.

The apt layer was cached; pinned renv/jsonlite restoration and full dependency closure/version validation executed again. Environment tests reject an altered R version and a lock missing BH and restore pinned abind into a clean temporary library. This is not a claim of rebuilding every OS package from an empty cache.

Initial guard tests used the validated v3.3 image. Final tests run in the new v3.4 image with the same package versions. Exact image identity and source hashes are in provenance/runtime_spec.json. No MCMC or research calculations occur in these environment tests.
