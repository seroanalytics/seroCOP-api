# Dockerfile for seroCOP-api with brms/Stan
FROM rocker/r-ver:4.3.1

ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
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

# Install R packages in order with error handling
RUN R -e "install.packages(c('plumber','jsonlite','readr','dplyr','tidyr','ggplot2','pROC','base64enc'), repos='https://cloud.r-project.org', Ncpus=4)" || exit 1

# Install brms and dependencies (slow)
RUN R -e "install.packages('loo', repos='https://cloud.r-project.org', Ncpus=4)" || exit 1
RUN R -e "install.packages('rstan', repos='https://cloud.r-project.org', Ncpus=4)" || exit 1
RUN R -e "install.packages('brms', repos='https://cloud.r-project.org', Ncpus=4)" || exit 1

# Install remotes and seroCOP
RUN R -e "install.packages('remotes', repos='https://cloud.r-project.org')" || exit 1
RUN R -e "remotes::install_github('seroanalytics/seroCOP')" || echo "seroCOP install failed, continuing..."

WORKDIR /app
COPY plumber.R /app/plumber.R

EXPOSE 8001
CMD ["R", "-e", "pr <- plumber::plumb('plumber.R'); pr$run(host='0.0.0.0', port=8001)"]
