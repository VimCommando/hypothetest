# Script Generation Guide

The Operator generates a sampling script as part of blueprint compilation when
`measure.diagnostics.during` is declared. The script is a generated artifact
like compose.yml — infrastructure the Operator produces, not code the LLM
runs interactively.

## Coordinator handoff

The Coordinator's `readiness.toon` tells the Operator what's available:

```toon
os: darwin
observation_packages[2]{name,status,note}:
  elasticsearch_api,verified,http://localhost:9200
  darwin_tools,verified,vm_stat iostat
```

Generate the script **only for verified packages**. Do not include collection
logic for packages the Coordinator reported as missing or failed. Do not
include platform-specific code for a platform that isn't the target.

## Data flow

```
hypothetest.yml            readiness.toon
       |                        |
  [Operator reads during block + available packages]
       |
  [generates sampling script scoped to platform + packages]
       |
  [script runs: background phase + foreground sampling]
       |
  evidence/during/<v>-<r>-<p>-<method>.toon   <- Analyst reads
  evidence/during/<v>-<r>-<p>-raw/             <- debugging archive
       |
  [Analyst interprets: steady state, limiters, patterns]
```

## Script structure

Bash by default. Use Python when `jq` is unavailable (Coordinator reports
`jq: missing` in readiness TOON).

The Operator generates one script per experiment. The script accepts the
variation, repeat, phase name, and phase command as arguments. The script is
invoked once per phase execution.

### Skeleton

This is the complete structure. The Operator adapts it per experiment —
filling in the collection functions for the active methods and verified
packages. Functions referenced here are defined in the "Signal extraction"
section below.

The script assumes the working directory is the evaluation root (the
directory containing `hypothetest.yml` and `generated/`). The Operator
sets this via `cd` before invocation. All output paths (`evidence/during/`)
are relative to this root.

```bash
#!/usr/bin/env bash
set -euo pipefail

# --- generated config ---
ES_URL="${ELASTICSEARCH_URL:-http://localhost:9200}"
INTERVAL=10
METHODS=(use)  # populated from diagnostics.during.methods

# --- arguments ---
VARIATION="$1"
REPEAT="$2"
PHASE_NAME="$3"
shift 3
PHASE_CMD=("$@")  # remaining args are the command + arguments

# --- output paths ---
OUTPUT_DIR="evidence/during"
RAW_DIR="$OUTPUT_DIR/${VARIATION}-${REPEAT}-${PHASE_NAME}-raw"
mkdir -p "$RAW_DIR"

# --- per-method TOON files (generated per active method) ---
METHOD_FILE_use="$OUTPUT_DIR/${VARIATION}-${REPEAT}-${PHASE_NAME}-use.toon"
# METHOD_FILE_latency=...  (Operator adds one line per active method)

# --- collection dispatch ---
# The Operator generates this function body based on active methods.
# Each method has its own collect_<method> function defined below.
collect_all() {
  local t=$1
  for method in "${METHODS[@]}"; do
    "collect_${method}" "$t" || echo "[error] t=$t method=$method"
  done
}

# --- phase lifecycle ---
echo "[start] variation=$VARIATION repeat=$REPEAT phase=$PHASE_NAME interval=${INTERVAL}s methods=${METHODS[*]}"

"${PHASE_CMD[@]}" &
PHASE_PID=$!

cleanup() { kill "$PHASE_PID" 2>/dev/null; wait "$PHASE_PID" 2>/dev/null; }
trap cleanup EXIT INT TERM

# --- write TOON headers (generated per active method) ---
write_headers() {
  cat > "$METHOD_FILE_use" <<'TOON'
method: use
interval: 10s
packages[1]: elasticsearch_api
samples[N]{t,cpu_pct,heap_pct,gc_old,gc_old_ms,gc_young,gc_young_ms,tp_write_q,tp_write_r,tp_search_q,tp_search_r,disk_total_bytes,disk_free_bytes}:
TOON
  # Operator adds one block per active method (latency, tsa, etc.)
}
write_headers

# --- sampling loop ---
START_TIME=$(date +%s)
T=0
while kill -0 "$PHASE_PID" 2>/dev/null; do
  SAMPLE_START=$(date +%s)
  collect_all "$T"
  SAMPLE_ELAPSED=$(( $(date +%s) - SAMPLE_START ))

  if (( SAMPLE_ELAPSED >= INTERVAL )); then
    echo "[skip] t=$T reason=collection_slow elapsed=${SAMPLE_ELAPSED}s"
  else
    sleep $(( INTERVAL - SAMPLE_ELAPSED ))
  fi
  T=$(( T + INTERVAL ))
done

wait "$PHASE_PID"
PHASE_EXIT=$?

ELAPSED=$(( $(date +%s) - START_TIME ))

if (( ELAPSED < 15 )); then
  echo "[skip] reason=short_phase elapsed=${ELAPSED}s"
else
  collect_all "$T" 2>/dev/null
fi

echo "[phase_complete] variation=$VARIATION repeat=$REPEAT phase=$PHASE_NAME elapsed=${ELAPSED}s exit=$PHASE_EXIT"
exit "$PHASE_EXIT"
```

Key design decisions in the skeleton:

- **`PHASE_CMD=("$@")`** — command passed as separate args, not a string.
  The Operator invokes: `./sample.sh baseline 1 load_data espipe load --input ./data/docs.ndjson`
- **Per-method TOON files** — each method writes its own file. No single
  monolithic samples file. Uses `$METHOD_FILE_<method>` variables (not
  associative arrays) for bash 3.2 compatibility on macOS.
- **`collect_all` dispatches to `collect_<method>`** — the Operator fills in
  only the method functions for active methods. Unused methods don't exist
  in the generated script.
- **Skip-on-slow** — if collection takes longer than the interval, skip
  instead of queuing. Log it.

### Stdout discipline

Stdout is for the LLM — one structured line per event. Every line costs
tokens.

```
[start] variation=baseline repeat=1 phase=load_data interval=10s methods=use
[sample] t=10 method=use cpu_pct=45 heap_pct=62 gc_old=3
[phase_complete] variation=baseline repeat=1 phase=load_data elapsed=185s exit=0
```

Detailed data goes to TOON files. Do not print raw API responses to stdout.

### Error handling

| Case | Behavior |
|---|---|
| Collection takes longer than interval | Skip, log `[skip] t=N reason=collection_slow` |
| Phase finishes mid-collection | Complete current sample, record phase exit |
| API endpoint temporarily unreachable | Log `[error] t=N method=M`, continue |
| Phase exits non-zero | Collect final sample, record exit code, do not abort |
| Phase duration <15s | Log `[skip] reason=short_phase`, write no samples |

### Idempotency

Output files are namespaced `<variation>-<repeat>-<phase>-<method>`. Re-running
a failed variation does not corrupt previous results.

## Signal extraction

Each method has a `collect_<method>` function. The Operator generates only the
functions for methods that are active in the experiment. Each function:

1. Hits the relevant API or tool
2. Archives raw output to `$RAW_DIR`
3. Extracts signals via jq (or Python fallback)
4. Appends one TOON row to the method's output file
5. Prints a summary `[sample]` line to stdout

### `collect_use` — USE method

Primary source: `_nodes/stats` (always available).

```bash
collect_use() {
  local t=$1
  local raw
  raw=$(curl -sf "$ES_URL/_nodes/stats/os,jvm,thread_pool,fs") || return 1
  echo "$raw" > "$RAW_DIR/nodes_stats_t${t}.json"

  local cpu_pct heap_pct gc_old gc_old_ms gc_young gc_young_ms
  local tp_write_q tp_write_r tp_search_q tp_search_r
  local disk_total disk_free

  cpu_pct=$(echo "$raw" | jq '[.nodes[].os.cpu.percent] | add / length | round')
  heap_pct=$(echo "$raw" | jq '[.nodes[].jvm.mem.heap_used_percent] | add / length | round')
  gc_old=$(echo "$raw" | jq '[.nodes[].jvm.gc.collectors.old.collection_count] | add')
  gc_old_ms=$(echo "$raw" | jq '[.nodes[].jvm.gc.collectors.old.collection_time_in_millis] | add')
  gc_young=$(echo "$raw" | jq '[.nodes[].jvm.gc.collectors.young.collection_count] | add')
  gc_young_ms=$(echo "$raw" | jq '[.nodes[].jvm.gc.collectors.young.collection_time_in_millis] | add')
  tp_write_q=$(echo "$raw" | jq '[.nodes[].thread_pool.write.queue] | add')
  tp_write_r=$(echo "$raw" | jq '[.nodes[].thread_pool.write.rejected] | add')
  tp_search_q=$(echo "$raw" | jq '[.nodes[].thread_pool.search.queue] | add')
  tp_search_r=$(echo "$raw" | jq '[.nodes[].thread_pool.search.rejected] | add')
  disk_total=$(echo "$raw" | jq '[.nodes[].fs.total.total_in_bytes] | add')
  disk_free=$(echo "$raw" | jq '[.nodes[].fs.total.free_in_bytes] | add')

  echo "  ${t},${cpu_pct},${heap_pct},${gc_old},${gc_old_ms},${gc_young},${gc_young_ms},${tp_write_q},${tp_write_r},${tp_search_q},${tp_search_r},${disk_total},${disk_free}" >> "$METHOD_FILE_use"
  echo "[sample] t=$t method=use cpu_pct=$cpu_pct heap_pct=$heap_pct gc_old=$gc_old tp_write_q=$tp_write_q"
}
```

When Linux host tools are verified, the Operator adds supplementary
extraction to the same function:

| Signal | Linux command | Extraction |
|---|---|---|
| Host CPU | `mpstat 1 1` | `tail -1`, parse `%usr + %sys` |
| Disk I/O | `iostat -x 1 1` | `tail -n +4`, parse `%util` per device |
| Memory | `free -b` | parse used/total from `Mem:` line |

When macOS darwin_tools are verified, supplement with:

| Signal | macOS command | Extraction |
|---|---|---|
| Memory pressure | `vm_stat` | parse pages free/active/wired |

These supplement the ES API signals — they don't replace them. The TOON
header gains additional columns when host tools are present.

### `collect_latency` — Latency method

```bash
collect_latency() {
  local t=$1
  local raw
  raw=$(curl -sf "$ES_URL/_nodes/stats/indices/search") || return 1
  echo "$raw" > "$RAW_DIR/search_stats_t${t}.json"

  local query_total query_time
  query_total=$(echo "$raw" | jq '[.nodes[].indices.search.query_total] | add')
  query_time=$(echo "$raw" | jq '[.nodes[].indices.search.query_time_in_millis] | add')

  echo "  ${t},${query_total},${query_time}" >> "$METHOD_FILE_latency"
  echo "[sample] t=$t method=latency query_total=$query_total query_time_ms=$query_time"
}
```

For percentile-level latency, the Operator generates a probe function that
runs a representative query and records wall-clock response time. This is
experiment-specific — the Operator writes the probe based on the blueprint's
search phases.

### `collect_tsa` — TSA method

```bash
collect_tsa() {
  local t=$1
  local tsa_dir="$OUTPUT_DIR/${VARIATION}-${REPEAT}-${PHASE_NAME}-tsa"
  mkdir -p "$tsa_dir"
  curl -sf "$ES_URL/_nodes/hot_threads?threads=5" > "$tsa_dir/hot_threads_t${t}.txt" || return 1
  echo "[sample] t=$t method=tsa archived=hot_threads_t${t}.txt"
}
```

`hot_threads` output is text, not JSON. The script archives it; the Analyst
interprets thread state fractions from the snapshots. No TOON row — TSA
produces a directory of text files, not a time-series.

### `collect_on_cpu` — On-CPU method

Linux only. Requires `perf` (Coordinator verifies `CAP_PERFMON` or root).

```bash
collect_on_cpu() {
  local t=$1
  local oncpu_dir="$OUTPUT_DIR/${VARIATION}-${REPEAT}-${PHASE_NAME}-on_cpu"
  mkdir -p "$oncpu_dir"
  perf record -g -p "$ES_PID" -o "$oncpu_dir/perf_t${t}.data" -- sleep 1 2>/dev/null || return 1
  perf script -i "$oncpu_dir/perf_t${t}.data" > "$oncpu_dir/perf_t${t}.txt" 2>/dev/null
  echo "[sample] t=$t method=on_cpu archived=perf_t${t}.data"
}
```

Like TSA, on-CPU produces archived data rather than time-series TOON rows.
The Analyst interprets the flame graph / top frames from the perf output.

### `collect_off_cpu` — Off-CPU method

Linux only. Requires `bpftrace` (Coordinator verifies `CAP_BPF` or root).

```bash
collect_off_cpu() {
  local t=$1
  local offcpu_dir="$OUTPUT_DIR/${VARIATION}-${REPEAT}-${PHASE_NAME}-off_cpu"
  mkdir -p "$offcpu_dir"
  timeout "${INTERVAL}s" bpftrace -e 'profile:hz:99 /pid == '"$ES_PID"'/ { @[kstack] = count(); }' \
    > "$offcpu_dir/offcpu_t${t}.txt" 2>/dev/null || true
  echo "[sample] t=$t method=off_cpu archived=offcpu_t${t}.txt"
}
```

Off-CPU also produces archived stack data. The Analyst identifies dominant
wait classes (I/O, lock, sleep) from the captured stacks.

`$ES_PID` is resolved by the Operator at script generation time — for
compose targets, it wraps commands with `docker exec` to access the JVM
process. Both `on_cpu` and `off_cpu` are only generated when the
Coordinator reports their packages as verified.

## TOON output specification

Each method writes its own TOON file. The `write_headers` function in the
skeleton generates these headers based on active methods.

### USE samples

```toon
method: use
interval: 10s
packages[1]: elasticsearch_api
samples[18]{t,cpu_pct,heap_pct,gc_old,gc_old_ms,gc_young,gc_young_ms,tp_write_q,tp_write_r,tp_search_q,tp_search_r,disk_total_bytes,disk_free_bytes}:
  0,12,45,0,0,0,0,0,0,0,0,107374182400,96636764160
  10,45,62,3,120,2,40,0,0,2,0,107374182400,95496069120
  20,78,71,5,340,4,85,12,0,4,0,107374182400,93415538688
```

When host tools add columns, the header expands:

```toon
samples[18]{t,cpu_pct,heap_pct,gc_old,gc_old_ms,...,host_cpu_usr,host_cpu_sys,disk_util_pct,mem_used_bytes,mem_total_bytes}:
```

### Latency samples

When the `latency` method is the primary investigation method, the
Operator may reduce the interval (e.g., 5s instead of the default 10s)
for finer-grained response time tracking. The interval is always declared
in the TOON header.

```toon
method: latency
interval: 5s
samples[N]{t,query_total,query_time_ms}:
  0,0,0
  5,1200,4500
  10,2450,9200
```

### TSA (no TOON — text archive)

```
evidence/during/baseline-1-load_data-tsa/
  hot_threads_t0.txt
  hot_threads_t10.txt
  hot_threads_t20.txt
```

### Output file layout

```
evidence/during/
  baseline-1-load_data-use.toon
  baseline-1-load_data-latency.toon
  baseline-1-load_data-tsa/
  baseline-1-load_data-raw/
    nodes_stats_t0.json
    nodes_stats_t10.json
    search_stats_t0.json
```

## Platform collection patterns

### Always available: elasticsearch_api

Every deployment target has the ES API. This is the minimum viable
observation source and the only source for cloud/existing targets.

Key endpoints for during-phase sampling:

| Endpoint | Signals | Interval cost |
|---|---|---|
| `_nodes/stats/os,jvm,thread_pool,fs` | CPU, heap, GC, thread pools, disk | ~5ms |
| `_nodes/stats/indices` | Indexing rate, search rate, merge activity | ~5ms |
| `_cat/thread_pool?format=json` | Queue depth, rejected counts | ~2ms |
| `_nodes/hot_threads` | Thread state snapshots (TSA) | ~50-200ms |

`_nodes/stats` with specific filters is cheap. Prefer filtered requests
(`/os,jvm,thread_pool`) over unfiltered `_nodes/stats` to keep response
size small.

### Linux: sysstat + procps

Available on most Linux hosts. The Coordinator verifies with `which iostat`,
`which vmstat`, etc.

```bash
# iostat: disk I/O utilization per device
iostat -x 1 1 | tail -n +4  # skip header, parse device lines

# mpstat: per-CPU utilization breakdown
mpstat 1 1 | tail -1  # %usr, %sys, %iowait, %idle

# vmstat: memory, swap, I/O, CPU summary
vmstat 1 2 | tail -1  # second sample (first is since-boot average)

# pidstat: per-process CPU/IO (when ES PID is known)
pidstat -p $ES_PID 1 1
```

### Linux: jdk_tools

When the ES JVM PID is accessible (compose with `docker exec` or local):

```bash
# GC activity detail
jstat -gcutil $ES_PID 1000 1

# Thread dump (TSA method)
jstack $ES_PID > "$RAW_DIR/jstack_t${T}.txt"
```

### Linux: perf, bpftrace, bcc_tools

Privileged tools. Coordinator checks CAP_BPF/CAP_PERFMON or root.

Only include in the generated script when the Coordinator reports them as
verified. These are supplementary — experiments work without them.

### macOS: darwin_tools

```bash
# Memory pressure
vm_stat | head -10  # pages free, active, inactive, wired

# I/O (limited compared to Linux iostat)
iostat -c 2  # second sample
```

macOS has no `mpstat`, `pidstat`, or `vmstat` equivalent with the same
output format. For macOS compose tests, the ES API provides the primary
observation signals; `darwin_tools` supplements with host memory pressure
only.

## Integration with the execution loop

The sampling script integrates into the Operator's existing execution loop
(see `operator-evaluation-guide.md`). Step 7 changes from:

```
execute evaluation phases
```

to:

```
execute evaluation phases via sampling script (when during is declared)
```

The sampling script wraps the phase command. The Operator invokes:

```bash
./generated/scripts/sample.sh "$VARIATION" "$REPEAT" "$PHASE_NAME" espipe load --input ./data/docs.ndjson --target benchmark-index
```

When `during` is not declared, the Operator runs phases directly as before.
