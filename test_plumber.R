# Minimal test to see if plumber starts
library(plumber)

#* @get /test
function() {
  list(status = "ok", message = "Plumber is working")
}

#* Health check
#* @get /health
function() {
  list(status = "ok", timestamp = Sys.time())
}
