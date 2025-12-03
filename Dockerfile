# Minimal Dockerfile for seroCOP-api
FROM rocker/r-ver:4.3.1

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libfontconfig1-dev \
    libfreetype6-dev \
    libpng-dev \
    libjpeg-dev \
    pandoc \
    && rm -rf /var/lib/apt/lists/*

# Install R packages
RUN R -e "install.packages(c('plumber','jsonlite','readr','dplyr','tidyr','ggplot2','loo','pROC','base64enc'), repos='https://cloud.r-project.org')"
# brms and Stan
RUN R -e "install.packages('brms', repos='https://cloud.r-project.org')"
RUN R -e "install.packages(c('rstan'), repos='https://cloud.r-project.org')"

# Install seroCOP from CRAN or fallback to GitHub
# If not on CRAN, use remotes to install from the local repo mount or GitHub
RUN R -e "if (!requireNamespace('seroCOP', quietly=TRUE)) install.packages('remotes', repos='https://cloud.r-project.org')"
# Note: you may COPY the local package and run remotes::install_local

WORKDIR /app
COPY plumber.R /app/plumber.R

EXPOSE 8001
CMD ["bash", "-lc", "R -e 'pr <- plumber::plumb(\"plumber.R\"); pr$run(host=\"0.0.0.0\", port=8001)' "]
