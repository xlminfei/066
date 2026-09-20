FROM rocker/r2u:24.04
RUN apt-get update && apt-get install -y --no-install-recommends \
    r-cran-brms r-cran-rstan r-cran-posterior r-cran-digest r-cran-jsonlite \
    && rm -rf /var/lib/apt/lists/*
RUN Rscript -e "stopifnot(getRversion() == '4.6.1', as.character(packageVersion('brms')) == '2.23.0', as.character(packageVersion('rstan')) == '2.32.7', as.character(packageVersion('posterior')) == '1.7.0', as.character(packageVersion('digest')) == '0.6.39', as.character(packageVersion('jsonlite')) == '2.0.0')"
WORKDIR /project
