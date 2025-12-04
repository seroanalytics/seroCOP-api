# plumber.R — entrypoint
# Run with: R -e "pr <- plumber::plumb('plumber.R'); pr$run(host='0.0.0.0', port=8001)"

library(plumber)
library(jsonlite)
library(readr)
library(dplyr)
library(tidyr)
library(ggplot2)
library(brms)
library(loo)
library(pROC)
# seroCOP should be installed in the environment
library(seroCOP)

#* @filter cors
function(req, res) {
  # Allow requests from GitHub Pages or custom domain
  origin <- req$HTTP_ORIGIN
  allowed_origins <- c(
    "https://seroanalytics.github.io",
    "https://seroanalytics.org",
    "http://localhost:8000"  # for local dev
  )
  
  if (origin %in% allowed_origins) {
    res$setHeader("Access-Control-Allow-Origin", origin)
  }
  
  res$setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
  res$setHeader("Access-Control-Allow-Headers", "Content-Type")
  
  if (req$REQUEST_METHOD == "OPTIONS") {
    res$status <- 200
    return(list())
  }
  plumber::forward()
}

#* Health check
#* @get /health
function(){ list(status="ok", package=as.character(utils::packageVersion("seroCOP"))) }

# helpers ---------------------------------------------------------------
serialize_plot <- function(p){
  # Return base64 PNG for ggplot
  tf <- tempfile(fileext = ".png")
  ggsave(tf, plot=p, width=6, height=4, dpi=120)
  enc <- base64enc::dataURI(file=tf, mime="image/png")
  unlink(tf)
  enc
}

safe_auc <- function(labels, probs){
  tryCatch({
    pROC::auc(labels, probs) |> as.numeric()
  }, error=function(e){ NA_real_ })
}

#* Fit seroCOP model
#* @param infected_col The name of the binary outcome column (default "infected")
#* @param titre_col The biomarker/titre column for single-biomarker fits (optional)
#* @param family Logistic by default; currently only binary
#* @param chains Number of chains
#* @param iter Iterations per chain
#* @post /fit
#* @serializer unboxedJSON
function(req, res, infected_col="infected", titre_col=NULL, family="bernoulli", chains=2, iter=1000){
  tryCatch({
    # Get the uploaded CSV file from the raw POST body
    if(is.null(req$postBody) || length(req$postBody) == 0){
      res$status <- 400
      return(list(error="No file data received"))
    }
    
    # Parse multipart form data manually
    content_type <- req$HTTP_CONTENT_TYPE
    if(!grepl("multipart/form-data", content_type, fixed=TRUE)){
      res$status <- 400
      return(list(error="Expected multipart/form-data content type"))
    }
    
    # Extract boundary from content type
    boundary_match <- regexpr("boundary=([^;]+)", content_type)
    if(boundary_match == -1){
      res$status <- 400
      return(list(error="No boundary found in content type"))
    }
    boundary <- sub("boundary=", "", regmatches(content_type, boundary_match))
    
    # Convert to character if raw
    if(is.raw(req$postBody)){
      post_text <- rawToChar(req$postBody)
    } else {
      post_text <- as.character(req$postBody)
    }
    
    # Split postBody by boundary to find CSV part
    parts <- strsplit(post_text, paste0("--", boundary))[[1]]
    
    csv_content <- NULL
    for(part in parts){
      if(grepl('name="csv"', part, fixed=TRUE)){
        # Extract content after headers (double newline)
        content_start <- regexpr("\r\n\r\n", part)
        if(content_start > 0){
          csv_content <- substring(part, content_start + 4)
          # Remove trailing boundary markers
          csv_content <- sub("\r\n$", "", csv_content)
          break
        }
      }
    }
    
    if(is.null(csv_content)){
      res$status <- 400
      return(list(error="Could not find CSV file in multipart data"))
    }
    
    # Write to temp file and read
    csv_path <- tempfile(fileext = ".csv")
    writeLines(csv_content, csv_path)
    
    cat("Reading CSV file from:", csv_path, "\n")
    df <- readr::read_csv(csv_path, show_col_types = FALSE)
    cat("Data loaded:", nrow(df), "rows,", ncol(df), "cols\n")
    cat("Column names:", paste(names(df), collapse=", "), "\n")
    
    if(!infected_col %in% names(df)){
      res$status <- 400
      return(list(error=sprintf("Missing infected_col '%s' in data", infected_col)))
    }
    df <- df |> dplyr::mutate(!!infected_col := as.integer(.data[[infected_col]]))

    # Determine titre column for single-biomarker fitting
    if(is.null(titre_col)){
      # Pick first numeric biomarker column excluding infected_col
      candidates <- names(df)[sapply(df, is.numeric)]
      candidates <- setdiff(candidates, infected_col)
      if(length(candidates) == 0){
        res$status <- 400
        return(list(error="No numeric biomarker/titre column found"))
      }
      titre_col <- candidates[[1]]
    }
    if(!titre_col %in% names(df)){
      res$status <- 400
      return(list(error=sprintf("Missing titre_col '%s' in data", titre_col)))
    }
    
    cat("Using titre column:", titre_col, "\n")

    # Build a simple brms formula analogous to SeroCOP single biomarker
    form <- stats::as.formula(sprintf("%s ~ s(%s)", infected_col, titre_col))
    cat("Fitting model with formula:", deparse(form), "\n")

    # Fit via brms (backend is Stan, runs on server)
    fit <- brms::brm(
      formula = form,
      data = df,
      family = brms::bernoulli(link = "logit"),
      chains = as.integer(chains),
      iter = as.integer(iter),
      cores = max(1L, parallel::detectCores() - 1L),
      refresh = 0
    )
    
    cat("Model fit complete\n")

    # Extract posterior draws and summaries
    draws <- brms::as_draws_df(fit)
    summ <- brms::posterior_summary(fit)
    loo_res <- tryCatch({
      brms::loo(fit)
    }, error=function(e) NULL)

    # Protection curve: predicted probability over a grid of titre
    grid <- data.frame(!!titre_col := seq(min(df[[titre_col]], na.rm=TRUE),
                                         max(df[[titre_col]], na.rm=TRUE), length.out=100))
    preds <- brms::posterior_epred(fit, newdata = grid)
    mean_prob <- colMeans(preds)
    prot_df <- data.frame(titre = grid[[titre_col]], prob = mean_prob)
    prot_plot <- ggplot(prot_df, aes(x=titre, y=prob)) +
      geom_line(color="#111") +
      theme_minimal(base_family = "Avenir") +
      labs(title="Protection Curve", y="P(Infected)")

    # ROC
    fitted_probs <- brms::posterior_epred(fit, newdata=df)
    avg_prob <- rowMeans(fitted_probs)
    auc <- safe_auc(df[[infected_col]], avg_prob)

    # Package response
    list(
      meta = list(
        infected_col = infected_col,
        titre_col = titre_col,
        chains = as.integer(chains),
        iter = as.integer(iter),
        n = nrow(df),
        auc = auc,
        loo = if(!is.null(loo_res)) list(elpd = loo_res$estimates["elpd_loo","Estimate"],
                                         p_loo = loo_res$estimates["p_loo","Estimate"]) else NULL
      ),
      summaries = summ |> tibble::as_tibble() |> dplyr::mutate(term = rownames(summ)) |> jsonlite::toJSON(auto_unbox = TRUE),
      protection_curve = prot_df,
      protection_curve_plot = serialize_plot(prot_plot),
      posterior_draws = head(draws, 1000) # downsample for payload size
    )
  }, error = function(e) {
    cat("ERROR:", e$message, "\n")
    cat("Traceback:\n")
    print(e)
    res$status <- 500
    return(list(error = paste("Server error:", e$message)))
  })
}
