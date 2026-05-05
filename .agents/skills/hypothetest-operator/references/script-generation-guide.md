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
       ↓                        ↓
  [Operator reads during block + available packages]
       ↓
  [generates sampling script scoped to platform + packages]
       ↓
  [script runs: background phase + foreground sampling]
       ↓
  evidence/during/<v>-<r>-<p>-samples.toon    ← Analyst reads
  evidence/during/<v>-<r>-<p>-raw/            ← debugging archive
       ↓
  [Analyst interprets: steady state, limiters, patterns]
```

## Script structure

Bash by default. Use Python when the experiment needs JSON parsing and `jq`
is unavailable (Coordinator reports this).

Every generated script follows this skeleton:

```bash
#!/usr/bin/env bash
set -euo pipefail

# --- config (generated from hypothetest.yml) ---
ES_URL="${ELASTICSEARCH_URL:-http://localhost:9200}"
INTERVAL=10
VARIATION="$1"
REPEAT="$2"
PHASE_CMD="$3"
OUTPUT_DIR="evidence/during"

# --- setup ---
mkdir -p "$OUTPUT_DIR"
SAMPLES_FILE="$OUTPUT_DIR/${VARIATION}-${REPEAT}-${PHASE_NAME}-samples.toon"
RAW_DIR="$OUTPUT_DIR/${VARIATION}-${REPEAT}-${PHASE_NAME}-raw"
mkdir -p "$RAW_DIR"

# --- phase lifecycle ---
$PHASE_CMD &
PHASE_PID=$!
trap 'kill $PHASE_PID 2>/dev/null; exit 1' INT TERM

# --- sampling loop ---
T=0
write_toon_header
while kill -0 "$PHASE_PID" 2>/dev/null; do
  collect_sample "$T"
  T=$((T + INTERVAL))
  sleep "$INTERVAL"
done

wait "$PHASE_PID"
PHASE_EXIT=$?

# --- finalize ---
collect_sample "$T"  # final sample
write_toon_footer
echo "[phase_complete] variation=$VARIATION repeat=$REPEAT elapsed=${T}s exit=$PHASE_EXIT"
```

### Stdout discipline

Stdout is for the LLM — one structured line per event. Every line costs
tokens.

```
[start] variation=baseline repeat=1 phase=load_data interval=10s packages=elasticsearch_api,darwin_tools
[sample] t=10 cpu_pct=45 heap_pct=62 gc_old=3
[phase_complete] variation=baseline repeat=1 phase=load_data elapsed=185s exit=0
```

Detailed data goes to files. Do not print raw API responses to stdout.

### Error handling

| Case | Behavior |
|---|---|
| Collection takes longer than interval | Skip, log `[skip] t=N reason=collection_slow` |
| Phase finishes mid-collection | Complete current sample, record phase exit |
| API endpoint temporarily unreachable | Log `[error] t=N reason=endpoint_unreachable`, continue |
| Phase exits non-zero | Collect final sample, record exit code, do not abort |
| Phase duration <15s | Log `[skip] reason=short_phase`, write no samples |

### Idempotency

Output files are namespaced `<variation>-<repeat>-<phase>`. Re-running a
failed variation does not corrupt previous results.

## Signal extraction

The script extracts **method signals**, not raw API responses. The method
defines what signals matter; the package provides the raw data; the script
extracts and normalizes.

### USE method signals

The USE method needs utilization, saturation, and error indicators per
resource. The primary source is `_nodes/stats`.

From `_nodes/stats` (always available):

```bash
collect_use_es() {
  local raw
  raw=$(curl -s "$ES_URL/_nodes/stats/os,jvm,thread_pool,fs")
  echo "$raw" > "$RAW_DIR/nodes_stats_t${T}.json"

  # Extract via jq (or Python fallback)
  local cpu_pct heap_pct heap_max gc_old gc_old_ms gc_young gc_young_ms
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

  echo "  ${T},${cpu_pct},${heap_pct},${gc_old},${gc_old_ms},${gc_young},${gc_young_ms},${tp_write_q},${tp_write_r},${tp_search_q},${tp_search_r},${disk_total},${disk_free}" >> "$SAMPLES_FILE"
}
```

From host tools (when available — **supplements** ES APIs, does not replace):

| Signal | Linux (sysstat/procps) | macOS (darwin_tools) |
|---|---|---|
| Host CPU | `mpstat 1 1` → `%usr + %sys` | `vm_stat` → not direct; use ES cpu_pct |
| Disk I/O util | `iostat -x 1 1` → `%util` | `iostat` → limited |
| Memory pressure | `free -b` → used/total | `vm_stat` → pages active/wired/free |
| Network | `ss -s` or `/proc/net/dev` | `netstat -ib` |

### Latency method signals

From `_nodes/stats` or Rally output:

```bash
collect_latency_es() {
  local raw
  raw=$(curl -s "$ES_URL/_nodes/stats/indices/search")
  echo "$raw" > "$RAW_DIR/search_stats_t${T}.json"

  local query_total query_time
  query_total=$(echo "$raw" | jq '[.nodes[].indices.search.query_total] | add')
  query_time=$(echo "$raw" | jq '[.nodes[].indices.search.query_time_in_millis] | add')

  echo "  ${T},${query_total},${query_time}" >> "$LATENCY_FILE"
}
```

For percentile-level latency, the script captures from Rally's output or
from a dedicated search probe loop (generate a probe function that runs
a representative query and records wall-clock time).

### TSA method signals

From `_nodes/hot_threads`:

```bash
collect_tsa_es() {
  local raw
  raw=$(curl -s "$ES_URL/_nodes/hot_threads?threads=5")
  echo "$raw" > "$RAW_DIR/hot_threads_t${T}.txt"
  # TSA interpretation is Analyst-side — the script archives the raw output
}
```

`hot_threads` output is text, not JSON. The script archives it; the Analyst
interprets thread state fractions from the archived snapshots.

## TOON output specification

### USE samples

```toon
method: use
interval: 10s
packages[2]: elasticsearch_api,darwin_tools
samples[18]{t,cpu_pct,heap_pct,gc_old,gc_old_ms,gc_young,gc_young_ms,tp_write_q,tp_write_r,tp_search_q,tp_search_r,disk_total_bytes,disk_free_bytes}:
  0,12,45,0,0,0,0,0,0,0,0,107374182400,96636764160
  10,45,62,3,120,2,40,0,0,2,0,107374182400,95496069120
  20,78,71,5,340,4,85,12,0,4,0,107374182400,93415538688
```

### Latency samples

```toon
method: latency
interval: 5s
samples[N]{t,query_total,query_time_ms,query_delta,time_delta_ms,avg_latency_ms}:
  0,0,0,0,0,0
  5,1200,4500,1200,4500,3.75
  10,2450,9200,1250,4700,3.76
```

### Combined (multiple methods)

When multiple methods are active, write separate TOON files per method:

```
evidence/during/baseline-1-load_data-use.toon
evidence/during/baseline-1-load_data-latency.toon
evidence/during/baseline-1-load_data-tsa/    (directory of text snapshots)
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
./generated/scripts/sample.sh "$VARIATION" "$REPEAT" "$PHASE_CMD"
```

When `during` is not declared, the Operator runs phases directly as before.
