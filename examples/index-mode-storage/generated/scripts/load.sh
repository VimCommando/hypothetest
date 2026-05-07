#!/usr/bin/env bash
set -euo pipefail

# Coordinator-generated: dataset loading wrapper for index-mode-storage
# Brackets loader invocation with [load] lines. Captures espipe output
# to per-variation/repeat artifacts. Passes through exit code.

VARIATION="$1"
REPEAT="$2"
LOADER="$3"
shift 3

PHASE_OUTPUT_DIR="${HYPOTHETEST_PHASE_OUTPUT_DIR:-phase-output}/${VARIATION}/${REPEAT}"
mkdir -p "${PHASE_OUTPUT_DIR}"

START_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
START_EPOCH=$(date +%s)

echo "[load] variation=${VARIATION} repeat=${REPEAT} loader=${LOADER} status=start"

if [[ "${HYPOTHETEST_DRY_RUN:-false}" == "true" ]]; then
  echo "[load] variation=${VARIATION} repeat=${REPEAT} loader=${LOADER} status=complete exit=0 dry_run=true"
  exit 0
fi

LOADER_EXIT=0
"${LOADER}" "$@" \
  > "${PHASE_OUTPUT_DIR}/espipe_output.json" \
  2> "${PHASE_OUTPUT_DIR}/espipe_stderr.log" \
  || LOADER_EXIT=$?

END_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
END_EPOCH=$(date +%s)
DURATION_SEC=$(( END_EPOCH - START_EPOCH ))

cat > "${PHASE_OUTPUT_DIR}/load_manifest.yml" <<EOF
phase: load_data
variation: ${VARIATION}
repeat: ${REPEAT}
loader: ${LOADER}
command: ${LOADER} $*
start: ${START_TIME}
end: ${END_TIME}
duration_sec: ${DURATION_SEC}
exit_code: ${LOADER_EXIT}
artifacts:
  stdout: espipe_output.json
  stderr: espipe_stderr.log
EOF

echo "[load] variation=${VARIATION} repeat=${REPEAT} loader=${LOADER} status=complete exit=${LOADER_EXIT} duration=${DURATION_SEC}s"
exit "${LOADER_EXIT}"
