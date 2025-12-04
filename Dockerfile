# Dockerfile for seroCOP-api with brms/Stan
# Use rocker/verse which has many packages pre-installed
FROM rocker/verse:4.3.1

ENV DEBIAN_FRONTEND=noninteractive

# Install additional system dependencies
RUN apt-get update && apt-get install -y \
    libsodium-dev \
    cmake \
    && rm -rf /var/lib/apt/lists/*

# Install plumber (verse doesn't have it)
RUN install2.r --error --skipinstalled \
    plumber \
    pROC \
    base64enc \
    loo

# Install Stan and brms (this takes time)
RUN install2.r --error --skipinstalled --ncpus -1 \
    rstan \
    brms

# Install seroCOP from GitHub
RUN R -e "remotes::install_github('seroanalytics/seroCOP')" || echo "seroCOP optional"

WORKDIR /app
COPY plumber.R /app/plumber.R

EXPOSE 8001
CMD ["R", "-e", "pr <- plumber::plumb('plumber.R'); pr$run(host='0.0.0.0', port=8001)"]
