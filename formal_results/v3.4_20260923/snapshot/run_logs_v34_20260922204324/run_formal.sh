#!/usr/bin/env bash
set -euo pipefail
trap 'exit_code=$?; printf "{\n  \"exitCode\": %s,\n  \"finishedAt\": \"%s\"\n}\n" "$exit_code" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > /run_logs/formal_process_exit.json' EXIT
printf "FORMAL_ALL_STARTED %s\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
Rscript /project/v34/src/v3_pipeline.R --stage all 2>&1 | tee /run_logs/05_formal_all.log
