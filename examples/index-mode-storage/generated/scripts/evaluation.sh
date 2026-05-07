#!/usr/bin/env bash

# Hypothetest evaluation runner — index-mode-storage
#
# Compiled by the Architect from hypothetest.yml using evaluation-template.sh.
# 5 variations, 3 repeats, randomized order.
# Phases per variation: reset, load_data, collect_before, force_merge, collect_after.
# No diagnostics.during — workload phases call commands directly.

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
    echo "    index-mode-storage evaluation runner."
    echo "    Compares store size and indexing throughput across 5 index mode/codec variations."
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
export ELASTICSEARCH_URL="${ELASTICSEARCH_URL:-http://ironhide.local:9200}"

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
    standard
    logsdb
    logsdb_synthetic_source
    standard_best_compression
    standard_best_compression_sorted
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

# ----- Variation Configuration -----

function variation_template() {
    case "$1" in
        standard)                         echo "templates/base-template.yml" ;;
        logsdb)                           echo "templates/logsdb-template.yml" ;;
        logsdb_synthetic_source)          echo "templates/logsdb-synthetic-source-template.yml" ;;
        standard_best_compression)        echo "templates/standard-best-compression-template.yml" ;;
        standard_best_compression_sorted) echo "templates/standard-best-compression-sorted-template.yml" ;;
        *) log_error "Unknown variation: $1"; return 1 ;;
    esac
}

function variation_template_name() {
    case "$1" in
        standard)                         echo "yelp-reviews-standard" ;;
        logsdb)                           echo "yelp-reviews-logsdb" ;;
        logsdb_synthetic_source)          echo "yelp-reviews-logsdb-synthetic-source" ;;
        standard_best_compression)        echo "yelp-reviews-standard-best-compression" ;;
        standard_best_compression_sorted) echo "yelp-reviews-standard-best-compression-sorted" ;;
        *) log_error "Unknown variation: $1"; return 1 ;;
    esac
}

function variation_pipeline() {
    case "$1" in
        logsdb|logsdb_synthetic_source) echo "templates/pipeline-date-to-timestamp.yml" ;;
        *) ;;
    esac
}

function variation_index_name() {
    variation_template_name "$1"
}

function variation_pipeline_name() {
    case "$1" in
        logsdb|logsdb_synthetic_source) echo "yelp-reviews-date-to-timestamp" ;;
        *) ;;
    esac
}

# ----- Generated Task Functions -----

function task_validate_prerequisites() {
    command -v espipe >/dev/null || { log_error "espipe not found"; return 1; }
    command -v esdiag >/dev/null || { log_error "esdiag not found"; return 1; }
    command -v curl >/dev/null || { log_error "curl not found"; return 1; }
    command -v jq >/dev/null || { log_error "jq not found"; return 1; }
    test -f "${HYPOTHETEST_PLAN}" || { log_error "Plan file missing: ${HYPOTHETEST_PLAN}"; return 1; }

    local license_type
    license_type=$(curl -sf "${ELASTICSEARCH_URL}/_license" | grep -o '"type":"[^"]*"' | cut -d'"' -f4) || true
    case "${license_type}" in
        trial|enterprise|platinum)
            log_info "License: ${license_type} — logsdb_synthetic_source eligible"
        ;;
        *)
            log_warn "License: ${license_type:-unknown} — logsdb_synthetic_source requires enterprise or trial license"
        ;;
    esac
}

function task_prepare_workspace() {
    ensure_directories
    cp "${HYPOTHETEST_PLAN}" "${HYPOTHETEST_EVALUATION_DIR}/hypothetest.yml"
    print_env > "${HYPOTHETEST_EVALUATION_DIR}/evaluation.env"

    generate_run_order
    printf '%s\n' "${RUN_ORDER[@]}" > "${HYPOTHETEST_EVALUATION_DIR}/run_order.txt"
    log_info "Run order ($(cyan "${#RUN_ORDER[@]}") slots): ${RUN_ORDER[*]}"
}

function task_compose_up() {
    run_cmd ./generated/scripts/compose-up.sh
}

function task_compose_down() {
    run_cmd ./generated/scripts/compose-down.sh
}

# Per-variation/repeat tasks — called dynamically from the execution loop

function do_reset() {
    local variation="$1" repeat="$2"
    run_cmd ./generated/scripts/reset.sh "${variation}" "${repeat}"
}

function do_load_data() {
    local variation="$1" repeat="$2"
    local template pipeline pipeline_name index_name
    template="$(variation_template "${variation}")"
    pipeline="$(variation_pipeline "${variation}")"
    pipeline_name="$(variation_pipeline_name "${variation}")"
    index_name="$(variation_index_name "${variation}")"

    if [[ -n "${pipeline}" ]]; then
        run_cmd ./generated/scripts/load.sh "${variation}" "${repeat}" \
            espipe \
            "datasets/yelp/yelp_academic_dataset_review.json" \
            "${ELASTICSEARCH_URL}/${index_name}" \
            --template "${template}" \
            --template-name "$(variation_template_name "${variation}")" \
            --batch-size 5000 \
            --pipeline "${pipeline}" \
            --pipeline-name "${pipeline_name}"
    else
        run_cmd ./generated/scripts/load.sh "${variation}" "${repeat}" \
            espipe \
            "datasets/yelp/yelp_academic_dataset_review.json" \
            "${ELASTICSEARCH_URL}/${index_name}" \
            --template "${template}" \
            --template-name "$(variation_template_name "${variation}")" \
            --batch-size 5000
    fi
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
    local index_name
    index_name="$(variation_index_name "${variation}")"
    mkdir -p "${output_dir}"

    curl -sf "${ELASTICSEARCH_URL}/${index_name}/_stats/store,segments" \
        > "${output_dir}/${phase_name}.json"
}

function do_force_merge() {
    local variation="$1" repeat="$2"
    local output_dir="${HYPOTHETEST_MEASUREMENTS_DIR}/${variation}/${repeat}"
    local index_name
    index_name="$(variation_index_name "${variation}")"
    mkdir -p "${output_dir}"

    curl -sf -X POST \
        "${ELASTICSEARCH_URL}/${index_name}/_forcemerge?max_num_segments=1&wait_for_completion=true" \
        > "${output_dir}/force_merge_result.json"
}

# ----- Execution Loop -----

function execute_slot() {
    local slot="$1"
    local variation="${slot%%:*}"
    local repeat="${slot##*:}"

    log_info "$(white "=== ${variation} repeat ${repeat} ===")"

    do_reset "${variation}" "${repeat}"

    do_collect_diagnostics "${variation}" "${repeat}" "before_load" \
        "_cluster/health,_nodes/stats,_cat/nodes?v&format=json"

    do_load_data "${variation}" "${repeat}"

    do_collect_store_stats "${variation}" "${repeat}" "store_after_load"

    do_collect_diagnostics "${variation}" "${repeat}" "after_load" \
        "_nodes/stats,_stats,_cat/segments?format=json,_cat/indices?v&format=json"

    do_force_merge "${variation}" "${repeat}"

    do_collect_store_stats "${variation}" "${repeat}" "store_after_force_merge"

    do_collect_diagnostics "${variation}" "${repeat}" "after_force_merge" \
        "_nodes/stats,_stats,_cat/segments?format=json,_cat/indices?v&format=json"
}

function task_run_evaluation() {
    for slot in "${RUN_ORDER[@]}"; do
        execute_slot "${slot}"
    done
}

function task_compare_results() {
    log_info "Comparison: baseline=standard candidates=logsdb,logsdb_synthetic_source,standard_best_compression,standard_best_compression_sorted"
    log_info "Method: bootstrap, alpha=0.05, correction=bonferroni"
    log_info "Effect thresholds: store_size>10%, throughput<20% degradation"
    log_info "Comparison data collected — Analyst role performs statistical analysis"
}

function task_write_evaluation_index() {
    local eval_file="${HYPOTHETEST_EVALUATION_DIR}/evaluation.yml"

    {
        cat <<EOF
plan: hypothetest.yml
run_id: ${HYPOTHETEST_RUN_ID}
start: ${EVAL_START_TIME}
end: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
variations:
EOF
        local _prev_nullglob
        _prev_nullglob=$(shopt -p nullglob) || true
        shopt -s nullglob

        for v in "${VARIATIONS[@]}"; do
            echo "  ${v}:"
            for (( r=1; r<=REPEATS; r++ )); do
                local m_dir="measurements/${v}/${r}"
                local p_dir="evidence/phase-output/${v}/${r}"
                local d_dir="evidence/diagnostics/${v}/${r}"
                echo "    repeat_${r}:"
                echo "      measurements:"
                for f in "${HYPOTHETEST_MEASUREMENTS_DIR}/${v}/${r}"/*.json; do
                    echo "        - ${m_dir}/$(basename "$f")"
                done
                echo "      phase_output:"
                for f in "${HYPOTHETEST_PHASE_OUTPUT_DIR}/${v}/${r}"/*; do
                    echo "        - ${p_dir}/$(basename "$f")"
                done
                echo "      diagnostics:"
                for f in "${HYPOTHETEST_DIAGNOSTICS_DIR}/${v}/${r}"/*.zip; do
                    echo "        - ${d_dir}/$(basename "$f")"
                done
            done
        done

        ${_prev_nullglob}
    } > "${eval_file}"

    log_info "Evaluation index written to $(cyan "${eval_file}")"
}

# ----- Generated Evaluation Plan -----

function print_plan() {
    cat <<'PLAN'
Generated task plan — index-mode-storage:
  Variations: standard, logsdb, logsdb_synthetic_source,
              standard_best_compression, standard_best_compression_sorted
  Repeats: 3
  Order: randomized (Fisher-Yates, seed from run-id)

  1. validate_prerequisites
  2. prepare_workspace
  3. compose_up
  4. run_evaluation (15 slots, randomized):
     per slot:
       a. reset (delete index, clear caches, verify green)
       b. collect_diagnostics before_load
       c. load_data (espipe with variation-specific template/pipeline)
       d. collect_store_stats after_load
       e. collect_diagnostics after_load
       f. force_merge (max_num_segments=1)
       g. collect_store_stats after_force_merge
       h. collect_diagnostics after_force_merge
  5. compare_results
  6. write_evaluation_index
  7. compose_down
PLAN
}

declare EVAL_START_TIME=""

function command_run() {
    cd "${blueprint_root}"
    EVAL_START_TIME="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    run_task validate_prerequisites
    run_task prepare_workspace
    run_task compose_up
    run_task run_evaluation
    run_task compare_results
    run_task write_evaluation_index
    run_task compose_down
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
