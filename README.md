# seroCOP-api

A minimal Plumber API that runs brms/Stan fits for seroCOP on the server and returns JSON + base64 plots. This supports the hybrid approach recommended by Alix: browser for UI, server for model fitting.

## Endpoints

- `GET /health`: basic health check and seroCOP version
- `POST /fit`: multipart/form-data upload with `csv` file and options

### POST /fit parameters
- `csv` (file): CSV dataset
- `infected_col` (string, default `infected`): binary outcome column
- `tire_col` (string, optional): biomarker/titre column; if omitted, first numeric column is chosen
- `chains` (int, default 2): Stan chains
- `iter` (int, default 1000): iterations per chain

## Run locally

```sh
R -e "pr <- plumber::plumb('plumber.R'); pr$run(host='0.0.0.0', port=8001)"
```

Or with Docker.

## Docker

The included `Dockerfile` uses `rocker/r-ver` and installs system deps + R packages.

```sh
# Build
docker build -t serocop-api:latest ./seroCOP-api
# Run
docker run --rm -p 8001:8001 serocop-api:latest
```

## Example cURL

```sh
curl -X POST \
  -F csv=@examples/example_data.csv \
  -F infected_col=infected \
  -F chains=2 \
  -F iter=1000 \
  http://localhost:8001/fit
```

## Integrate with seroCOP-web

- In the browser, detect if the dataset requires server fitting (i.e., brms/Stan). If yes, POST to `/fit` and render returned plot and metrics.
- For small demos, keep the client-side simplified glm path; otherwise offload to this API.
