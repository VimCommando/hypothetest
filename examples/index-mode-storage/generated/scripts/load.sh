#!/usr/bin/env bash
set -euo pipefail

# Coordinator-generated: dataset loading wrapper for index-mode-storage
# Thin wrapper around espipe — adds structured stdout and passes through exit code.

VARIATION="$1"
REPEAT="$2"
LOADER="$3"
shift 3

ES_URL="${ELASTICSEARCH_URL:-http://ironhide.local:9200}"
EVAL_DIR="${HYPOTHETEST_EVALUATION_DIR:-.}"

echo "[start] variation=${VARIATION} repeat=${REPEAT} loader=${LOADER}"

if [[ "${HYPOTHETEST_DRY_RUN:-false}" == "true" ]]; then
  echo "[complete] dry_run=true"
  exit 0
fi

OUTPUT_DIR="${EVAL_DIR}/evidence/phase-output/${VARIATION}/${REPEAT}"
mkdir -p "${OUTPUT_DIR}"

"${LOADER}" "$@" 2>&1 | tee "${OUTPUT_DIR}/load_output.txt"
LOADER_EXIT=${PIPESTATUS[0]}

echo "[complete] variation=${VARIATION} repeat=${REPEAT} loader=${LOADER} exit=${LOADER_EXIT}"
exit "${LOADER_EXIT}"
