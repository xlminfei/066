FROM rocker/r2u:24.04@sha256:dc2a96c3b368969635c25c177c64514ba8e37cf2259dd3584de7c33520191d92
# Build context must be this version's directory, which contains renv.lock.
# r2u supplies prebuilt binaries for speed. The restore step below enforces the
# complete locked R dependency closure and restores any mismatching versions.
RUN apt-get update && apt-get install -y --no-install-recommends \
    r-cran-brms r-cran-rstan r-cran-posterior r-cran-digest \
    ca-certificates curl cmake pandoc \
    && rm -rf /var/lib/apt/lists/*
COPY renv.lock /opt/ratio-analysis-v3.3/renv.lock
COPY scripts/restore_environment.R /opt/ratio-analysis-v3.3/scripts/restore_environment.R
RUN Rscript /opt/ratio-analysis-v3.3/scripts/restore_environment.R \
    --lockfile /opt/ratio-analysis-v3.3/renv.lock \
    --library /usr/local/lib/R/site-library
ENV RATIO_V33_LOCKFILE=/opt/ratio-analysis-v3.3/renv.lock
WORKDIR /project
