#!/usr/bin/env bash

# Hypothetest evaluation runner — eck-generic-ingest
#
# 2 variations (default-heap, larger-heap), 3 repeats, randomized order.
# Applies kustomize overlays between variations to change heap/memory.
# Phases per variation/repeat: reset, load_data, collect_stats, diagnostics.

set -Eeuo pipefail

# ----- Logging Functions -----

declare log_name="hypothetest-evaluation"
declare colorize=false
if [[ -t 1 ]]; then
    colorize=true
fi

function echo_color() {
    local color=$1; shift
    if [[ $colorize == true ]]; then
        printf "\033[%sm%b\033[39m" "${color}" "${*}"
    else
        printf "%b" "${*}"
    fi
}

function red()       { echo_color 31 "${@}"; }
function green()     { echo_color 32 "${@}"; }
function yellow()    { echo_color 33 "${@}"; }
function blue()      { echo_color 34 "${@}"; }
function magenta()   { echo_color 35 "${@}"; }
function cyan()      { echo_color 36 "${@}"; }
function gray()      { echo_color 90 "${@}"; }
function white()     { echo_color 97 "${@}"; }

function timestamp() { date -u +"%Y-%m-%d %H:%M:%S"; }
function log_error() { echo "[$(timestamp) $(red Error) ${log_name}] ${*}"; }
function log_warn()  { echo "[$(timestamp) $(yellow Warn)  ${log_name}] ${*}"; }
function log_info()  { echo "[$(timestamp) $(green Info)  ${log_name}] ${*}"; }
function log_debug() {
    if [[ ${LOG_LEVEL:-info} == "debug" ]]; then
        echo "[$(timestamp) $(blue Debug) ${log_name}] ${*}"
    fi
}

# ----- Help Functions -----

function print_usage() {
    echo "$(white "Usage:") evaluation.sh <command> [options]"
}

function print_help_main() {
    white "Description:\n"
    echo "    eck-generic-ingest evaluation runner."
    echo "    Compares indexing throughput across 2 heap configurations on ECK."
    echo
    white "Usage:\n"
    echo "    $(green ./generated/scripts/evaluation.sh) <command> [options]"
    echo
    white "Commands:\n"
    echo "    $(green run)       Execute the compiled evaluation plan"
    echo "    $(green plan)      Print the generated task plan"
    echo "    $(green env)       Print resolved environment configuration"
    echo "    $(green help)      Print help for this script"
    echo
    white "Options:\n"
    echo "    -e, --env <FILE>       Source environment variables from FILE"
    echo "    -o, --output <DIR>     Evaluation output root"
    echo "    -r, --run-id <ID>      Stable run identifier"
    echo "    -n, --dry-run          Print commands without executing task bodies"
    echo "    -d, --debug            Enable debug logging"
    echo "        --no-color         Disable colorized output"
    echo "        --seed <INT>       Randomization seed (default: derived from run-id)"
    echo "        --version          Print template version"
    echo
}

# ----- Environment Configuration -----

declare template_version="0.1.0"
declare script_dir
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
declare blueprint_root
blueprint_root="$(cd "${script_dir}/../.." && pwd)"

declare env_file=""
declare command="run"
declare seed=""

export LOG_LEVEL="${LOG_LEVEL:-info}"
export HYPOTHETEST_PLAN="${HYPOTHETEST_PLAN:-${blueprint_root}/hypothetest.yml}"
export HYPOTHETEST_EVALUATION_ROOT="${HYPOTHETEST_EVALUATION_ROOT:-${blueprint_root}/evaluations}"
export HYPOTHETEST_RUN_ID="${HYPOTHETEST_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
export HYPOTHETEST_DRY_RUN="${HYPOTHETEST_DRY_RUN:-false}"
export ELASTICSEARCH_URL="${ELASTICSEARCH_URL:-http://localhost:9200}"

declare NAMESPACE="${HYPOTHETEST_K8S_NAMESPACE:-hypothetest}"
declare CLUSTER_NAME="hypothetest"
declare HEALTH_TIMEOUT=300
declare HEALTH_INTERVAL=10

function env_file_source() {
    if [[ -z ${env_file} ]]; then
        return 0
    fi
    if [[ ! -f ${env_file} ]]; then
        log_error "Environment file $(magenta "${env_file}") not found"
        exit 1
    fi
    log_debug "Sourcing $(gray "${env_file}")"
    # shellcheck disable=SC1090
    source "${env_file}"
}

function environment_setup() {
    export HYPOTHETEST_EVALUATION_DIR="${HYPOTHETEST_EVALUATION_ROOT}/${HYPOTHETEST_RUN_ID}"
    export HYPOTHETEST_EVIDENCE_DIR="${HYPOTHETEST_EVALUATION_DIR}/evidence"
    export HYPOTHETEST_RAW_DIR="${HYPOTHETEST_EVIDENCE_DIR}/raw"
    export HYPOTHETEST_PHASE_OUTPUT_DIR="${HYPOTHETEST_EVIDENCE_DIR}/phase-output"
    export HYPOTHETEST_DIAGNOSTICS_DIR="${HYPOTHETEST_EVIDENCE_DIR}/diagnostics"
    export HYPOTHETEST_LOG_DIR="${HYPOTHETEST_EVALUATION_DIR}/logs"
    export HYPOTHETEST_MEASUREMENTS_DIR="${HYPOTHETEST_EVALUATION_DIR}/measurements"
    export HYPOTHETEST_COMPARISONS_DIR="${HYPOTHETEST_EVALUATION_DIR}/comparisons"
}

function print_env() {
    echo "HYPOTHETEST_PLAN=${HYPOTHETEST_PLAN}"
    echo "HYPOTHETEST_EVALUATION_ROOT=${HYPOTHETEST_EVALUATION_ROOT}"
    echo "HYPOTHETEST_RUN_ID=${HYPOTHETEST_RUN_ID}"
    echo "HYPOTHETEST_EVALUATION_DIR=${HYPOTHETEST_EVALUATION_DIR}"
    echo "HYPOTHETEST_DRY_RUN=${HYPOTHETEST_DRY_RUN}"
    echo "ELASTICSEARCH_URL=${ELASTICSEARCH_URL}"
    echo "NAMESPACE=${NAMESPACE}"
    echo "LOG_LEVEL=${LOG_LEVEL}"
}

# ----- Process Control -----

declare current_task=""

function on_error() {
    local status=$?
    if [[ -n ${current_task} ]]; then
        log_error "Task $(magenta "${current_task}") failed with exit status ${status}"
    else
        log_error "Evaluation failed with exit status ${status}"
    fi
    exit "${status}"
}

trap on_error ERR

function ensure_directories() {
    mkdir -p \
        "${HYPOTHETEST_RAW_DIR}" \
        "${HYPOTHETEST_PHASE_OUTPUT_DIR}" \
        "${HYPOTHETEST_DIAGNOSTICS_DIR}" \
        "${HYPOTHETEST_LOG_DIR}" \
        "${HYPOTHETEST_MEASUREMENTS_DIR}" \
        "${HYPOTHETEST_COMPARISONS_DIR}"
}

function run_cmd() {
    log_info "$(green running) $(white "$*")"
    if [[ ${HYPOTHETEST_DRY_RUN} == "true" ]]; then
        return 0
    fi
    "$@"
}

function task_function_name() {
    local task="${1//-/_}"
    echo "task_${task}"
}

function run_task() {
    local task="$1"
    local fn
    fn="$(task_function_name "${task}")"
    if ! declare -f "${fn}" >/dev/null; then
        log_error "Task function $(magenta "${fn}") is not defined"
        return 1
    fi

    current_task="${task}"
    log_info "$(green start) task $(cyan "${task}")"
    if [[ ${HYPOTHETEST_DRY_RUN} == "true" ]]; then
        log_info "$(yellow dry-run) task $(cyan "${task}") would execute $(white "${fn}")"
    else
        "${fn}" > "${HYPOTHETEST_LOG_DIR}/${task}.log" 2>&1
    fi
    log_info "$(green complete) task $(cyan "${task}")"
    current_task=""
}

# ----- Variations and Randomization -----

declare -a VARIATIONS=(
    default-heap
    larger-heap
)

declare REPEATS=3

function generate_run_order() {
    local run_seed="${seed:-$(echo "${HYPOTHETEST_RUN_ID}" | cksum | cut -d' ' -f1)}"
    log_info "Randomization seed: $(cyan "${run_seed}")"

    local -a slots=()
    for v in "${VARIATIONS[@]}"; do
        for (( r=1; r<=REPEATS; r++ )); do
            slots+=("${v}:${r}")
        done
    done

    RUN_ORDER=()
    local i n temp
    n=${#slots[@]}
    RANDOM=${run_seed}
    for (( i=n-1; i>0; i-- )); do
        local j=$(( RANDOM % (i + 1) ))
        temp="${slots[$i]}"
        slots[$i]="${slots[$j]}"
        slots[$j]="${temp}"
    done
    RUN_ORDER=("${slots[@]}")
}

# ----- Kubernetes Variation Management -----

declare CURRENT_VARIATION=""

function apply_variation() {
    local variation="$1"
    if [[ "${variation}" == "${CURRENT_VARIATION}" ]]; then
        log_info "Variation $(cyan "${variation}") already applied, skipping"
        return 0
    fi

    log_info "$(white "Applying kustomize overlay:") $(cyan "${variation}")"
    kubectl apply -k "${blueprint_root}/generated/eck/overlays/${variation}"

    log_info "Waiting for cluster health green (timeout ${HEALTH_TIMEOUT}s)"
    local elapsed=0
    while (( elapsed < HEALTH_TIMEOUT )); do
        local phase health
        phase=$(kubectl get elasticsearch "${CLUSTER_NAME}" -n "${NAMESPACE}" \
            -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        health=$(kubectl get elasticsearch "${CLUSTER_NAME}" -n "${NAMESPACE}" \
            -o jsonpath='{.status.health}' 2>/dev/null || echo "")

        if [[ "${phase}" == "Ready" && "${health}" == "green" ]]; then
            log_info "Cluster healthy after $(cyan "${elapsed}s") for variation $(cyan "${variation}")"
            CURRENT_VARIATION="${variation}"
            return 0
        fi

        sleep "${HEALTH_INTERVAL}"
        elapsed=$(( elapsed + HEALTH_INTERVAL ))
    done

    log_error "Health timeout for variation ${variation} after ${elapsed}s"
    return 1
}

function ensure_port_forward() {
    local pf_pidfile="${HYPOTHETEST_EVALUATION_ROOT:-.}/port-forward.pid"
    local pf_pid=""
    if [[ -f "${pf_pidfile}" ]]; then
        pf_pid=$(cat "${pf_pidfile}")
    fi

    if [[ -n "${pf_pid}" ]] && kill -0 "${pf_pid}" 2>/dev/null; then
        if curl -sf "${ELASTICSEARCH_URL}/_cluster/health" >/dev/null 2>&1; then
            return 0
        fi
        log_info "Port-forward alive but ES unreachable, restarting"
        kill "${pf_pid}" 2>/dev/null || true
    else
        log_info "Port-forward not running, restarting"
    fi

    kubectl port-forward -n "${NAMESPACE}" "service/${CLUSTER_NAME}-es-http" 9200:9200 &
    local new_pid=$!
    echo "${new_pid}" > "${pf_pidfile}"
    sleep 3

    if ! kill -0 "${new_pid}" 2>/dev/null; then
        log_error "Port-forward restart failed"
        return 1
    fi
    if ! curl -sf "${ELASTICSEARCH_URL}/_cluster/health" >/dev/null 2>&1; then
        log_error "ES unreachable after port-forward restart"
        return 1
    fi
    log_info "Port-forward restored (PID ${new_pid})"
}

# ----- Generated Task Functions -----

function task_validate_prerequisites() {
    command -v espipe >/dev/null || { log_error "espipe not found"; return 1; }
    command -v esdiag >/dev/null || { log_error "esdiag not found"; return 1; }
    command -v curl >/dev/null || { log_error "curl not found"; return 1; }
    command -v jq >/dev/null || { log_error "jq not found"; return 1; }
    command -v kubectl >/dev/null || { log_error "kubectl not found"; return 1; }
    test -f "${HYPOTHETEST_PLAN}" || { log_error "Plan file missing: ${HYPOTHETEST_PLAN}"; return 1; }

    if ! kubectl get elasticsearch "${CLUSTER_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
        log_error "Elasticsearch CRD not found — run eck-up.sh first"
        return 1
    fi

    local health
    health=$(curl -sf "${ELASTICSEARCH_URL}/_cluster/health" 2>/dev/null) || {
        log_error "Cannot reach Elasticsearch at ${ELASTICSEARCH_URL} — is port-forward running?"
        return 1
    }
    log_info "Cluster reachable at $(cyan "${ELASTICSEARCH_URL}")"
}

function task_prepare_workspace() {
    ensure_directories
    cp "${HYPOTHETEST_PLAN}" "${HYPOTHETEST_EVALUATION_DIR}/hypothetest.yml"
    print_env > "${HYPOTHETEST_EVALUATION_DIR}/evaluation.env"

    generate_run_order
    printf '%s\n' "${RUN_ORDER[@]}" > "${HYPOTHETEST_EVALUATION_DIR}/run_order.txt"
    log_info "Run order ($(cyan "${#RUN_ORDER[@]}") slots): ${RUN_ORDER[*]}"
}

# Per-variation/repeat tasks

function do_reset() {
    local variation="$1" repeat="$2"
    local es_url="${ELASTICSEARCH_URL}"

    echo "[reset] variation=${variation} repeat=${repeat}"

    curl -sf -X DELETE "${es_url}/benchmark-index" -o /dev/null || true
    echo "[reset] action=delete_indices index=benchmark-index"

    curl -sf -X POST "${es_url}/_cache/clear" -o /dev/null
    echo "[reset] action=clear_caches"

    local health status
    health=$(curl -sf "${es_url}/_cluster/health?wait_for_status=green&timeout=30s")
    status=$(echo "${health}" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)

    if [[ "${status}" != "green" ]]; then
        echo "[reset] action=verify_cluster_green status=${status} result=failed"
        return 1
    fi
    echo "[reset] action=verify_cluster_green status=green"
}

function do_load_data() {
    local variation="$1" repeat="$2"
    local phase_output_dir="${HYPOTHETEST_PHASE_OUTPUT_DIR}/${variation}/${repeat}"
    mkdir -p "${phase_output_dir}"

    local start_time start_epoch
    start_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    start_epoch=$(date +%s)

    echo "[load] variation=${variation} repeat=${repeat} loader=espipe status=start"

    local loader_exit=0
    espipe \
        "data/docs.ndjson" \
        "${ELASTICSEARCH_URL}/benchmark-index" \
        --batch-size 5000 \
        > "${phase_output_dir}/espipe_output.json" \
        2> "${phase_output_dir}/espipe_stderr.log" \
        || loader_exit=$?

    local end_time end_epoch duration_sec
    end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    end_epoch=$(date +%s)
    duration_sec=$(( end_epoch - start_epoch ))

    cat > "${phase_output_dir}/load_manifest.yml" <<EOF
phase: load_data
variation: ${variation}
repeat: ${repeat}
loader: espipe
command: espipe data/docs.ndjson ${ELASTICSEARCH_URL}/benchmark-index --batch-size 5000
start: ${start_time}
end: ${end_time}
duration_sec: ${duration_sec}
exit_code: ${loader_exit}
artifacts:
  stdout: espipe_output.json
  stderr: espipe_stderr.log
EOF

    echo "[load] variation=${variation} repeat=${repeat} loader=espipe status=complete exit=${loader_exit} duration=${duration_sec}s"
    return "${loader_exit}"
}

function do_collect_diagnostics() {
    local variation="$1" repeat="$2" collection_point="$3" apis="$4"
    local output_dir="${HYPOTHETEST_DIAGNOSTICS_DIR}/${variation}/${repeat}"
    mkdir -p "${output_dir}"

    run_cmd esdiag collect \
        --host "${ELASTICSEARCH_URL}" \
        --apis "${apis}" \
        --output "${output_dir}/${collection_point}.zip"
}

function do_collect_store_stats() {
    local variation="$1" repeat="$2" phase_name="$3"
    local output_dir="${HYPOTHETEST_MEASUREMENTS_DIR}/${variation}/${repeat}"
    mkdir -p "${output_dir}"

    curl -sf "${ELASTICSEARCH_URL}/benchmark-index/_stats/store,indexing,segments" \
        > "${output_dir}/${phase_name}.json"
}

# ----- Execution Loop -----

function execute_slot() {
    local slot="$1"
    local variation="${slot%%:*}"
    local repeat="${slot##*:}"

    log_info "$(white "=== ${variation} repeat ${repeat} ===")"

    apply_variation "${variation}"
    ensure_port_forward

    do_reset "${variation}" "${repeat}"

    do_collect_diagnostics "${variation}" "${repeat}" "before_load" \
        "_cluster/health,_nodes/stats,_cat/nodes?v&format=json"

    do_load_data "${variation}" "${repeat}"

    do_collect_store_stats "${variation}" "${repeat}" "stats_after_load"

    do_collect_diagnostics "${variation}" "${repeat}" "after_load" \
        "_nodes/stats,_stats,_cat/segments?format=json,_cat/indices?v&format=json"
}

function task_run_evaluation() {
    VARIATION_TIMINGS_FILE="${HYPOTHETEST_EVALUATION_DIR}/.variation_timings"
    : > "${VARIATION_TIMINGS_FILE}"
    for slot in "${RUN_ORDER[@]}"; do
        local slot_start slot_end slot_secs variation
        slot_start=$(date +%s)
        execute_slot "${slot}"
        slot_end=$(date +%s)
        slot_secs=$(( slot_end - slot_start ))
        variation="${slot%%:*}"
        echo "${variation} ${slot_secs}" >> "${VARIATION_TIMINGS_FILE}"
    done
}

function task_compare_results() {
    log_info "Comparison: baseline=default-heap candidate=larger-heap"
    log_info "Method: bootstrap, alpha=0.05, one-tailed"
    log_info "Effect threshold: indexing_throughput_docs_per_sec > 10%"
    log_info "Comparison data collected — Analyst role performs statistical analysis"
}

# ----- Evaluation Index -----

function task_write_evaluation_index() {
    local eval_file="${HYPOTHETEST_EVALUATION_DIR}/evaluation.yml"
    local eval_end
    eval_end="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    local eval_start_epoch eval_end_epoch total_seconds
    eval_start_epoch="$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "${EVAL_START_TIME}" +%s 2>/dev/null || date -d "${EVAL_START_TIME}" +%s 2>/dev/null || echo 0)"
    eval_end_epoch="$(date +%s)"
    total_seconds=$(( eval_end_epoch - eval_start_epoch ))

    local _prev_nullglob
    _prev_nullglob=$(shopt -p nullglob) || true
    shopt -s nullglob

    {
        cat <<EOF
name: eck-generic-ingest
evaluation_id: ${HYPOTHETEST_RUN_ID}
hypothesis: hypothesis.md
plan: hypothetest.yml
manifest:
  started_at: "${EVAL_START_TIME}"
  completed_at: "${eval_end}"
  status: complete
  blueprint: blueprint.yml
  plan: hypothetest.yml
  quality: environment-dependent
  variations:
EOF
        for v in "${VARIATIONS[@]}"; do
            echo "    - ${v}"
        done

        cat <<EOF
  repeats: ${REPEATS}
  runtime:
    total_seconds: ${total_seconds}
    variations:
EOF
        for v in "${VARIATIONS[@]}"; do
            local vsecs=0
            if [[ -f "${VARIATION_TIMINGS_FILE}" ]]; then
                vsecs=$(awk -v var="$v" '$1 == var { total += $2 } END { print total+0 }' "${VARIATION_TIMINGS_FILE}")
            fi
            echo "      - variation: ${v}"
            echo "        seconds: ${vsecs}"
        done

        cat <<EOF
  failures: []
evidence:
  raw: []
  diagnostics:
EOF
        for v in "${VARIATIONS[@]}"; do
            for (( r=1; r<=REPEATS; r++ )); do
                for f in "${HYPOTHETEST_DIAGNOSTICS_DIR}/${v}/${r}"/*.zip; do
                    echo "    - path: evidence/diagnostics/${v}/${r}/$(basename "$f")"
                    echo "      kind: diagnostic"
                    echo "      format: zip"
                done
            done
        done

        echo "  phase_output:"
        for v in "${VARIATIONS[@]}"; do
            for (( r=1; r<=REPEATS; r++ )); do
                for f in "${HYPOTHETEST_PHASE_OUTPUT_DIR}/${v}/${r}"/*; do
                    local bname ext kind_fmt
                    bname="$(basename "$f")"
                    ext="${bname##*.}"
                    case "${ext}" in
                        json) kind_fmt="format: json" ;;
                        log)  kind_fmt="format: log" ;;
                        yml)  kind_fmt="format: yml" ;;
                        *)    kind_fmt="format: txt" ;;
                    esac
                    echo "    - path: evidence/phase-output/${v}/${r}/${bname}"
                    echo "      kind: phase_output"
                    echo "      ${kind_fmt}"
                done
            done
        done

        echo "  generated: []"

        echo "measurements:"
        echo "  normalized: []"
        echo "  primary:"
        echo "    - indexing_throughput_docs_per_sec"
        echo "    - store_size_after_load"
        echo "  secondary:"
        echo "    - segment_count_after_load"
        echo "    - indexing_time_millis"

        echo "comparisons:"
        echo "  artifacts: []"
        echo "  baseline: default-heap"
        echo "  candidates:"
        echo "    - larger-heap"

        echo "# report: generated by Analyst role after evaluation"
    } > "${eval_file}"

    ${_prev_nullglob}

    log_info "Evaluation index written to $(cyan "${eval_file}")"
}

# ----- Generated Evaluation Plan -----

function print_plan() {
    cat <<'PLAN'
Generated task plan — eck-generic-ingest:
  Variations: default-heap (baseline), larger-heap (candidate)
  Repeats: 3
  Order: randomized (Fisher-Yates, seed from run-id)

  1. validate_prerequisites
  2. prepare_workspace
  3. run_evaluation (6 slots, randomized):
     per slot:
       a. apply_variation (kustomize overlay, wait for green health)
       b. reset (delete index, clear caches, verify green)
       c. collect_diagnostics before_load
       d. load_data (espipe, capture to espipe_output.json)
       e. collect_store_stats after_load
       f. collect_diagnostics after_load
  4. compare_results (log-only — Analyst performs analysis)
  5. write_evaluation_index
PLAN
}

declare EVAL_START_TIME=""
VARIATION_TIMINGS_FILE=""

function command_run() {
    cd "${blueprint_root}"
    EVAL_START_TIME="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    run_task validate_prerequisites
    run_task prepare_workspace
    run_task run_evaluation
    run_task compare_results
    run_task write_evaluation_index
    log_info "$(green complete) evaluation artifacts at $(cyan "${HYPOTHETEST_EVALUATION_DIR}")"
}

# ----- Process command line arguments -----

if [[ $# -gt 0 ]]; then
    command="${1}" && shift
fi

if [[ ! ${command} =~ ^(run|plan|env|help|-?-?h(elp)?)$ ]]; then
    log_error "Invalid command $(magenta "${command}")"
    print_help_main
    exit 1
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--debug)
            export LOG_LEVEL="debug"
            shift
        ;;
        -e|--env)
            shift
            if [[ $# -eq 0 ]]; then
                log_error "Missing environment filename"
                exit 1
            fi
            env_file="${1}"
            shift
        ;;
        -n|--dry-run)
            export HYPOTHETEST_DRY_RUN="true"
            shift
        ;;
        -o|--output)
            shift
            if [[ $# -eq 0 ]]; then
                log_error "Missing output directory"
                exit 1
            fi
            export HYPOTHETEST_EVALUATION_ROOT="${1}"
            shift
        ;;
        -r|--run-id)
            shift
            if [[ $# -eq 0 ]]; then
                log_error "Missing run id"
                exit 1
            fi
            export HYPOTHETEST_RUN_ID="${1}"
            shift
        ;;
        --seed)
            shift
            if [[ $# -eq 0 ]]; then
                log_error "Missing seed value"
                exit 1
            fi
            seed="${1}"
            shift
        ;;
        --no-color)
            colorize=false
            shift
        ;;
        --version)
            echo "${template_version}"
            exit 0
        ;;
        *)
            log_error "Unknown option $(magenta "${1}")"
            print_usage
            exit 1
        ;;
    esac
done

env_file_source
environment_setup
log_debug "Input command: $(white "${command}")"

case "${command}" in
    "help"|"-h"|"--help" )
        print_help_main
    ;;
    "plan" )
        print_plan
    ;;
    "env" )
        print_env
    ;;
    "run" )
        command_run
    ;;
esac
