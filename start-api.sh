#!/usr/bin/env zsh
R -e "pr <- plumber::plumb('plumber.R'); pr\$run(host='0.0.0.0', port=8001)"