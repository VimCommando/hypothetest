#!/usr/bin/env bash
set -euo pipefail

# Coordinator-generated: dataset loading wrapper for index-mode-storage
# Brackets loader invocation with [load] lines. Passes through exit code.

VARIATION="$1"
REPEAT="$2"
LOADER="$3"
shift 3

echo "[load] variation=${VARIATION} repeat=${REPEAT} loader=${LOADER} status=start"

if [[ "${HYPOTHETEST_DRY_RUN:-false}" == "true" ]]; then
  echo "[load] variation=${VARIATION} repeat=${REPEAT} loader=${LOADER} status=complete exit=0 dry_run=true"
  exit 0
fi

LOADER_EXIT=0
"${LOADER}" "$@" || LOADER_EXIT=$?

echo "[load] variation=${VARIATION} repeat=${REPEAT} loader=${LOADER} status=complete exit=${LOADER_EXIT}"
exit "${LOADER_EXIT}"
