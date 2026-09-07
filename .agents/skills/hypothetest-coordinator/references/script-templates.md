# Script Templates

Template catalog for generating `sample.sh` — the during-phase observation
script. The Coordinator reads `readiness.toon` and the experiment's
`diagnostics.during` configuration, then stamps out sample.sh by selecting
the appropriate patterns from this catalog.

This is a pattern catalog: complete, annotated examples the Coordinator
adapts per experiment. Not parameterized `{{variable}}` templates.

## Input contract

The Coordinator generates sample.sh after readiness validation. Two inputs
drive generation decisions:

**readiness.toon** — what's available on the target platform:
```toon
os: darwin
tq: verified
observation_packages[2]{name,status,note}:
  elasticsearch_api,verified,http://localhost:9200
  darwin_tools,verified,vm_stat iostat
```

**diagnostics.during** from hypothetest.yml — what the Architect prescribed:
```yaml
diagnostics:
  during:
    profile: standard
    methods: [use]
    interval: 10s
```

Generation rules:
- Generate collection functions **only for verified packages**
- Do not include platform-specific code for a platform that isn't the target
- Resolve profile to method set (see `observation-methods.md` profiles table)
- When explicit methods are listed alongside a profile, union them

## Data flow

```
hypothetest.yml            readiness.toon
       |                        |
  [Coordinator reads during block + available packages]
       |
  [generates sample.sh scoped to platform + packages]
       |
  [evaluation.sh calls sample.sh per phase]
       |
  [sample.sh: background phase + foreground sampling]
       |
  ${HYPOTHETEST_EVIDENCE_DIR}/during/<v>-<r>-<p>-<method>.toon  <- Analyst reads
  ${HYPOTHETEST_EVIDENCE_DIR}/during/<v>-<r>-<p>-raw/            <- debugging archive
```

## Skeleton

Complete structure. The Coordinator adapts it per experiment — filling in the
collection functions for the active methods and verified packages from the
catalog below.

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

# --- output paths (absolute, from evaluation.sh env vars) ---
DURING_DIR="${HYPOTHETEST_EVIDENCE_DIR}/during"
RAW_DIR="$DURING_DIR/${VARIATION}-${REPEAT}-${PHASE_NAME}-raw"
mkdir -p "$RAW_DIR"

# --- per-method TOON files (generated per active method) ---
METHOD_FILE_use="$DURING_DIR/${VARIATION}-${REPEAT}-${PHASE_NAME}-use.toon"
# METHOD_FILE_latency=...  (Coordinator adds one line per active method)

# --- collection dispatch ---
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
  # Coordinator adds one block per active method (latency, tsa, etc.)
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

PHASE_EXIT=0
wait "$PHASE_PID" || PHASE_EXIT=$?

ELAPSED=$(( $(date +%s) - START_TIME ))

if (( ELAPSED < 15 )); then
  echo "[skip] reason=short_phase elapsed=${ELAPSED}s"
else
  collect_all "$T" 2>/dev/null
fi

echo "[phase_complete] variation=$VARIATION repeat=$REPEAT phase=$PHASE_NAME elapsed=${ELAPSED}s exit=$PHASE_EXIT"
exit "$PHASE_EXIT"
```

### Skeleton design decisions

- **`PHASE_CMD=("$@")`** — command passed as separate args, not a string.
- **Per-method TOON files** — each method writes its own file. Uses
  `$METHOD_FILE_<method>` variables (not associative arrays) for bash 3.2
  compatibility on macOS.
- **`collect_all` dispatches to `collect_<method>`** — the Coordinator fills
  in only the method functions for active methods. Unused methods don't
  exist in the generated script.
- **Skip-on-slow** — if collection takes longer than the interval, skip
  instead of queuing. Log it.
- **Output paths use env vars** — `${HYPOTHETEST_EVIDENCE_DIR}/during/`,
  not relative paths. Prevents artifacts landing under the blueprint root.
- **Bash with tq.** Verify tq and every generated filter during readiness. If tq is missing, install it through Coordinator setup or block required sampling. User-declared Python phases remain separate prerequisites.

### Stdout discipline

Stdout carries structured `[tag] key=value` lines. evaluation.sh's
`run_task` captures these to log files — the Operator reads the log files.

```
[start] variation=baseline repeat=1 phase=load_data interval=10s methods=use
[sample] t=10 method=use cpu_pct=45 heap_pct=62 gc_old=3
[skip] t=120 reason=collection_slow elapsed=12s
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
a failed variation overwrites that run's artifacts, not others.

## Collection function catalog

Each `collect_<method>` function follows the same contract:

1. Hit the relevant API or tool
2. Archive raw output to `$RAW_DIR`
3. Extract signals with verified tq filters
4. Append one TOON row to the method's output file
5. Print a summary `[sample]` line to stdout

### `collect_use` — elasticsearch_api (always available)

```bash
collect_use() {
  local t=$1
  local raw
  raw=$(curl -sf "$ES_URL/_nodes/stats/os,jvm,thread_pool,fs") || return 1
  echo "$raw" > "$RAW_DIR/nodes_stats_t${t}.json"

  local cpu_pct heap_pct gc_old gc_old_ms gc_young gc_young_ms
  local tp_write_q tp_write_r tp_search_q tp_search_r
  local disk_total disk_free

  cpu_pct=$(echo "$raw" | tq -x -e -r '[.nodes[].os.cpu.percent] | add / length') || return 1
  heap_pct=$(echo "$raw" | tq -x -e -r '[.nodes[].jvm.mem.heap_used_percent] | add / length') || return 1
  gc_old=$(echo "$raw" | tq -x -e -r '[.nodes[].jvm.gc.collectors.old.collection_count] | add') || return 1
  gc_old_ms=$(echo "$raw" | tq -x -e -r '[.nodes[].jvm.gc.collectors.old.collection_time_in_millis] | add') || return 1
  gc_young=$(echo "$raw" | tq -x -e -r '[.nodes[].jvm.gc.collectors.young.collection_count] | add') || return 1
  gc_young_ms=$(echo "$raw" | tq -x -e -r '[.nodes[].jvm.gc.collectors.young.collection_time_in_millis] | add') || return 1
  tp_write_q=$(echo "$raw" | tq -x -e -r '[.nodes[].thread_pool.write.queue] | add') || return 1
  tp_write_r=$(echo "$raw" | tq -x -e -r '[.nodes[].thread_pool.write.rejected] | add') || return 1
  tp_search_q=$(echo "$raw" | tq -x -e -r '[.nodes[].thread_pool.search.queue] | add') || return 1
  tp_search_r=$(echo "$raw" | tq -x -e -r '[.nodes[].thread_pool.search.rejected] | add') || return 1
  disk_total=$(echo "$raw" | tq -x -e -r '[.nodes[].fs.total.total_in_bytes] | add') || return 1
  disk_free=$(echo "$raw" | tq -x -e -r '[.nodes[].fs.total.free_in_bytes] | add') || return 1

  for value in "$cpu_pct" "$heap_pct" "$gc_old" "$gc_old_ms" "$gc_young" "$gc_young_ms" "$tp_write_q" "$tp_write_r" "$tp_search_q" "$tp_search_r" "$disk_total" "$disk_free"; do
    [[ "$value" =~ ^-?[0-9]+([.][0-9]+)?$ ]] || return 1
  done

  echo "  ${t},${cpu_pct},${heap_pct},${gc_old},${gc_old_ms},${gc_young},${gc_young_ms},${tp_write_q},${tp_write_r},${tp_search_q},${tp_search_r},${disk_total},${disk_free}" >> "$METHOD_FILE_use"
  echo "[sample] t=$t method=use cpu_pct=$cpu_pct heap_pct=$heap_pct gc_old=$gc_old tp_write_q=$tp_write_q"
}
```

### `collect_use` supplement — sysstat (Linux)

When readiness.toon reports `sysstat: verified`, the Coordinator adds these
extractions to the `collect_use` function body. The TOON header gains
additional columns.

| Signal | Command | Extraction |
|---|---|---|
| host_cpu_usr, host_cpu_sys | `mpstat 1 1` | `tail -1`, parse `%usr + %sys` |
| disk_util_pct | `iostat -x 1 1` | `tail -n +4`, parse `%util` per device |
| mem_used, mem_total | `free -b` | parse `Mem:` line |

### `collect_use` supplement — darwin_tools (macOS)

When readiness.toon reports `darwin_tools: verified`:

| Signal | Command | Extraction |
|---|---|---|
| mem_free, mem_active, mem_wired | `vm_stat` | parse pages free/active/wired |

macOS has no `mpstat`, `pidstat`, or `vmstat` equivalent. ES API provides the
primary signals; `darwin_tools` supplements with host memory pressure only.

### `collect_latency`

```bash
collect_latency() {
  local t=$1
  local raw
  raw=$(curl -sf "$ES_URL/_nodes/stats/indices/search") || return 1
  echo "$raw" > "$RAW_DIR/search_stats_t${t}.json"

  local query_total query_time
  query_total=$(echo "$raw" | tq -x -e -r '[.nodes[].indices.search.query_total] | add')
  query_time=$(echo "$raw" | tq -x -e -r '[.nodes[].indices.search.query_time_in_millis] | add')

  [[ "$query_total" =~ ^[0-9]+$ && "$query_time" =~ ^[0-9]+$ ]] || return 1

  echo "  ${t},${query_total},${query_time}" >> "$METHOD_FILE_latency"
  echo "[sample] t=$t method=latency query_total=$query_total query_time_ms=$query_time"
}
```

For percentile-level latency, the Coordinator generates a probe function that
runs a representative query and records wall-clock response time. This is
experiment-specific — the probe is based on the blueprint's search phases.

### `collect_tsa`

```bash
collect_tsa() {
  local t=$1
  local tsa_dir="$DURING_DIR/${VARIATION}-${REPEAT}-${PHASE_NAME}-tsa"
  mkdir -p "$tsa_dir"
  curl -sf "$ES_URL/_nodes/hot_threads?threads=5" > "$tsa_dir/hot_threads_t${t}.txt" || return 1
  echo "[sample] t=$t method=tsa archived=hot_threads_t${t}.txt"
}
```

No TOON rows — TSA produces a directory of text files.

### `collect_on_cpu` (Linux only)

Requires `perf` — Coordinator verifies `CAP_PERFMON` or root.

```bash
collect_on_cpu() {
  local t=$1
  local oncpu_dir="$DURING_DIR/${VARIATION}-${REPEAT}-${PHASE_NAME}-on_cpu"
  mkdir -p "$oncpu_dir"
  perf record -g -p "$ES_PID" -o "$oncpu_dir/perf_t${t}.data" -- sleep 1 2>/dev/null || return 1
  perf script -i "$oncpu_dir/perf_t${t}.data" > "$oncpu_dir/perf_t${t}.txt" 2>/dev/null
  echo "[sample] t=$t method=on_cpu archived=perf_t${t}.data"
}
```

### `collect_off_cpu` (Linux only)

Requires `bpftrace` — Coordinator verifies `CAP_BPF` or root.

```bash
collect_off_cpu() {
  local t=$1
  local offcpu_dir="$DURING_DIR/${VARIATION}-${REPEAT}-${PHASE_NAME}-off_cpu"
  mkdir -p "$offcpu_dir"
  timeout "${INTERVAL}s" bpftrace -e 'profile:hz:99 /pid == '"$ES_PID"'/ { @[kstack] = count(); }' \
    > "$offcpu_dir/offcpu_t${t}.txt" 2>/dev/null || true
  echo "[sample] t=$t method=off_cpu archived=offcpu_t${t}.txt"
}
```

### `$ES_PID` resolution

`$ES_PID` is used by `on_cpu` and `off_cpu`. The Coordinator templates the
resolution logic into sample.sh — it cannot be hardcoded because the cluster
isn't running at generation time.

For compose targets:
```bash
ES_PID=$(docker exec <container_name> pgrep -f elasticsearch)
```

For ECK targets:
```bash
ES_POD=$(kubectl get pods -n "${NAMESPACE}" -l elasticsearch.k8s.elastic.co/cluster-name="${CLUSTER_NAME}" -o jsonpath='{.items[0].metadata.name}')
ES_PID=$(kubectl exec -n "${NAMESPACE}" "${ES_POD}" -- pgrep -f elasticsearch)
```

For local/existing targets with direct JVM access:
```bash
ES_PID=$(pgrep -f elasticsearch)
```

The Coordinator determines the resolution pattern from readiness.toon
(deployment target, engine, container name).

## Platform collection patterns

### elasticsearch_api (always available)

Every deployment target has the ES API. Minimum viable observation source.

| Endpoint | Signals | Interval cost |
|---|---|---|
| `_nodes/stats/os,jvm,thread_pool,fs` | CPU, heap, GC, thread pools, disk | ~5ms |
| `_nodes/stats/indices` | Indexing rate, search rate, merge activity | ~5ms |
| `_cat/thread_pool?format=json` | Queue depth, rejected counts | ~2ms |
| `_nodes/hot_threads` | Thread state snapshots (TSA) | ~50-200ms |

Prefer filtered requests (`/os,jvm,thread_pool`) over unfiltered
`_nodes/stats` to keep response size small.

### sysstat + procps (Linux)

Coordinator verifies with `which iostat`, `which vmstat`, etc.

```bash
iostat -x 1 1 | tail -n +4    # disk I/O utilization per device
mpstat 1 1 | tail -1           # per-CPU utilization: %usr, %sys, %iowait, %idle
vmstat 1 2 | tail -1           # memory, swap, I/O, CPU summary
pidstat -p $ES_PID 1 1         # per-process CPU/IO (when PID known)
```

### jdk_tools (Linux, compose with docker exec)

When the ES JVM PID is accessible:

```bash
jstat -gcutil $ES_PID 1000 1                # GC activity detail
jstack $ES_PID > "$RAW_DIR/jstack_t${T}.txt"  # thread dump (TSA)
```

### jdk_tools (ECK, via kubectl exec)

Same JDK tools, accessed through kubectl instead of docker exec:

```bash
kubectl exec -n "${NAMESPACE}" "${ES_POD}" -- jstat -gcutil $ES_PID 1000 1
kubectl exec -n "${NAMESPACE}" "${ES_POD}" -- jstack $ES_PID > "$RAW_DIR/jstack_t${T}.txt"
```

### perf, bpftrace, bcc_tools (Linux, privileged)

Coordinator checks CAP_BPF/CAP_PERFMON or root. Only include when verified.
Supplementary — experiments work without them.

### darwin_tools (macOS)

```bash
vm_stat | head -10    # pages free, active, inactive, wired
iostat -c 2           # I/O (limited compared to Linux)
```

### ECK observation differences

When `deployment.target: kubernetes`, the ES API observation methods work
unchanged (they hit the Elasticsearch endpoint the same way). The
differences are in host/container-level tools:

| Compose | ECK equivalent |
|---|---|
| `docker exec <container> <cmd>` | `kubectl exec -n <ns> <pod> -- <cmd>` |
| `docker logs <container>` | `kubectl logs -n <ns> <pod>` |
| `docker stats` (CPU/memory) | `kubectl top pods -n <ns>` |
| `docker exec <container> pgrep -f elasticsearch` | `kubectl exec -n <ns> <pod> -- pgrep -f elasticsearch` |

`esdiag` works unchanged — it hits the ES endpoint, not the container
runtime.

Pod log collection:
```bash
kubectl logs -n "${NAMESPACE}" "${ES_POD}" > "$RAW_DIR/es_log_t${T}.txt"
```

Container-level resource usage (requires metrics-server):
```bash
kubectl top pods -n "${NAMESPACE}" --no-headers
```
