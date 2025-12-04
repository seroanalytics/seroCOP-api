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

# Install R packages one by one to catch errors
# Show detailed output for plumber installation
RUN R -e "options(warn=2); install.packages('plumber', repos='https://cloud.r-project.org', dependencies=TRUE)"

RUN R -e "install.packages(c('jsonlite','readr','dplyr','tidyr','ggplot2','pROC','base64enc'), repos='https://cloud.r-project.org', Ncpus=4, dependencies=TRUE)"

# Install brms dependencies
RUN R -e "install.packages('loo', repos='https://cloud.r-project.org', Ncpus=4, dependencies=TRUE)"
RUN R -e "install.packages('rstan', repos='https://cloud.r-project.org', Ncpus=4, dependencies=TRUE)"
RUN R -e "install.packages('brms', repos='https://cloud.r-project.org', Ncpus=4, dependencies=TRUE)"

# Install remotes and seroCOP
RUN R -e "install.packages('remotes', repos='https://cloud.r-project.org', dependencies=TRUE)"
RUN R -e "remotes::install_github('seroanalytics/seroCOP')" || echo "seroCOP install optional"

WORKDIR /app
COPY plumber.R /app/plumber.R

EXPOSE 8001
CMD ["R", "-e", "pr <- plumber::plumb('plumber.R'); pr$run(host='0.0.0.0', port=8001)"]
