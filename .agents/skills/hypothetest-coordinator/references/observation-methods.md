# Observation Methods

Method catalog for during-phase observation. The Coordinator uses this to
generate correct collection functions in `sample.sh`. The Analyst uses it to
interpret what the collected signals mean.

Each method entry is self-contained: packages, key signals, collection shape,
output format, and interpretation pattern. No cross-referencing needed.

## Methods

### `use` — Utilization, Saturation, Errors

Investigates resource bottlenecks. The foundation method — always available
because `elasticsearch_api` is present on every deployment target.

- **Packages:** `elasticsearch_api` (always), `sysstat` (Linux), `procps` (Linux), `darwin_tools` (macOS)
- **Key signals:** CPU util, disk I/O util, memory pressure, thread pool queue/rejected, GC frequency
- **Analyst pattern:** saturated resource = limiter. Report per-variation x phase.
- **Limiter taxonomy:** `cpu`, `memory`, `disk_io`, `network`, `gc_pressure`, `lock_contention`, `thread_pool_saturation`, `merge_throttle`, `app_internal`, `unknown`

**Collection shape — elasticsearch_api (always):**

Primary source: `_nodes/stats/os,jvm,thread_pool,fs`. Signals extracted via
jq from the JSON response. One TOON row per sample interval.

| Signal | jq path | Notes |
|---|---|---|
| cpu_pct | `.nodes[].os.cpu.percent` | avg across nodes |
| heap_pct | `.nodes[].jvm.mem.heap_used_percent` | avg across nodes |
| gc_old / gc_old_ms | `.nodes[].jvm.gc.collectors.old.collection_count` | cumulative |
| gc_young / gc_young_ms | `.nodes[].jvm.gc.collectors.young.collection_count` | cumulative |
| tp_write_q / tp_write_r | `.nodes[].thread_pool.write.queue` / `.rejected` | sum across nodes |
| tp_search_q / tp_search_r | `.nodes[].thread_pool.search.queue` / `.rejected` | sum across nodes |
| disk_total / disk_free | `.nodes[].fs.total.total_in_bytes` / `.free_in_bytes` | sum across nodes |

**Collection shape — sysstat (Linux supplement):**

| Signal | Command | Extraction |
|---|---|---|
| host_cpu_usr, host_cpu_sys | `mpstat 1 1` | `tail -1`, parse `%usr + %sys` |
| disk_util_pct | `iostat -x 1 1` | `tail -n +4`, parse `%util` per device |
| mem_used, mem_total | `free -b` | parse `Mem:` line |

**Collection shape — darwin_tools (macOS supplement):**

| Signal | Command | Extraction |
|---|---|---|
| mem_free, mem_active, mem_wired | `vm_stat` | parse pages free/active/wired |

Host tool signals supplement the ES API signals — they don't replace them.
When present, the TOON header gains additional columns.

**TOON output:**
```toon
method: use
interval: 10s
packages[1]: elasticsearch_api
samples[N]{t,cpu_pct,heap_pct,gc_old,gc_old_ms,gc_young,gc_young_ms,tp_write_q,tp_write_r,tp_search_q,tp_search_r,disk_total_bytes,disk_free_bytes}:
  0,12,45,0,0,0,0,0,0,0,0,107374182400,96636764160
  10,45,62,3,120,2,40,0,0,2,0,107374182400,95496069120
```

### `latency` — Response Time Analysis

Investigates response time distribution shape.

- **Packages:** `elasticsearch_api` (always), `rally` (when rally is the workload tool), `bpftrace` (Linux, deep)
- **Key signals:** p50, p90, p99, p99/p50 ratio, histogram shape, query_total, query_time_ms
- **Analyst pattern:** bimodal detection, moving modes, outlier fraction
- **Schema effect:** auto-sets `shape: percentile_set` or `histogram` on relevant metrics

**Collection shape — elasticsearch_api:**

Primary source: `_nodes/stats/indices/search`. Tracks cumulative query
totals and time.

| Signal | jq path |
|---|---|
| query_total | `.nodes[].indices.search.query_total` (sum) |
| query_time_ms | `.nodes[].indices.search.query_time_in_millis` (sum) |

For percentile-level latency, the Coordinator generates a probe function
that runs a representative query and records wall-clock response time.
This is experiment-specific — the probe is based on the blueprint's search
phases.

When the `latency` method is the primary investigation method, the
Coordinator may reduce the sampling interval (e.g., 5s instead of default
10s) for finer-grained response time tracking. The interval is declared
in the TOON header.

**TOON output:**
```toon
method: latency
interval: 5s
samples[N]{t,query_total,query_time_ms}:
  0,0,0
  5,1200,4500
  10,2450,9200
```

### `tsa` — Thread State Analysis

Investigates where thread time goes.

- **Packages:** `elasticsearch_api` (hot_threads), `jdk_tools` (jstack, jcmd — Linux/compose only)
- **Key signals:** Execute, Runnable, Sleep, Lock, Idle fractions
- **Analyst pattern:** flag any state >10% that isn't Execute or Idle

**Collection shape:**

`hot_threads` output is text, not JSON. The collection function archives
each snapshot as a text file. No TOON rows — TSA produces a directory of
text files, not a time-series.

```bash
curl -sf "$ES_URL/_nodes/hot_threads?threads=5" > "$tsa_dir/hot_threads_t${t}.txt"
```

When `jdk_tools` are available (compose target with JVM PID accessible),
also capture `jstack` thread dumps for deeper state analysis.

**Output layout (directory, not TOON file):**
```
evidence/during/<variation>-<repeat>-<phase>-tsa/
  hot_threads_t0.txt
  hot_threads_t10.txt
  hot_threads_t20.txt
```

### `on_cpu` — On-CPU Analysis

Investigates where CPU cycles go. Linux only.

- **Packages:** `perf` (requires CAP_PERFMON or root), `elasticsearch_api` (hot_threads as fallback)
- **Key signals:** CPU flame graph top frames, IPC, branch misses
- **Analyst pattern:** hot path identification, differential flame graph between variations

**Collection shape:**

```bash
perf record -g -p "$ES_PID" -o "$oncpu_dir/perf_t${t}.data" -- sleep 1
perf script -i "$oncpu_dir/perf_t${t}.data" > "$oncpu_dir/perf_t${t}.txt"
```

`$ES_PID` is resolved at runtime within `sample.sh` — the Coordinator
templates the resolution logic (e.g., `docker exec <container> pgrep -f
elasticsearch` for compose targets) but the PID cannot be known at
generation time.

Like TSA, on-CPU produces archived data rather than time-series TOON rows.

**Output layout (directory, not TOON file):**
```
evidence/during/<variation>-<repeat>-<phase>-on_cpu/
  perf_t0.data
  perf_t0.txt
  perf_t10.data
  perf_t10.txt
```

### `off_cpu` — Off-CPU Analysis

Investigates where threads block. Linux only.

- **Packages:** `bpftrace` (requires CAP_BPF or root), `perf`
- **Key signals:** blocked-time stacks, I/O wait, lock wait, sleep wait
- **Analyst pattern:** identify dominant wait class, correlate with USE saturation signals

**Collection shape:**

```bash
timeout "${INTERVAL}s" bpftrace -e \
  'profile:hz:99 /pid == '"$ES_PID"'/ { @[kstack] = count(); }' \
  > "$offcpu_dir/offcpu_t${t}.txt"
```

`$ES_PID` resolved at runtime (same as on_cpu).

Off-CPU produces archived stack data. The Analyst identifies dominant wait
classes (I/O, lock, sleep) from the captured stacks.

**Output layout (directory, not TOON file):**
```
evidence/during/<variation>-<repeat>-<phase>-off_cpu/
  offcpu_t0.txt
  offcpu_t10.txt
```

### `drill_down` — Root Cause Drill-Down

Not a during-phase method and not a pipeline artifact. This is an Analyst
mental model: when a regression is identified, the Analyst narrows from
system-level signals to the specific layer causing the issue. It does not
appear in `diagnostics.during.methods`, has no `collect_drill_down`
function, and produces no TOON files. It is purely an interpretation
pattern the Analyst applies when writing the report.

## Profiles

Named method combinations. Profiles map to method sets; the Coordinator
resolves each method to the packages verified in readiness.toon.

| Profile | Methods | Minimum packages | Use when |
|---|---|---|---|
| `none` | -- | -- | Explicitly disable during-phase observation |
| `light` | `use` (ES APIs only) | `elasticsearch_api` | Latency-sensitive; minimize observer effect |
| `standard` | `use` (full) | `elasticsearch_api`, `sysstat`, `procps` | Default recommendation |
| `comprehensive` | `use`, `tsa`, `latency`, `on_cpu` | all available | Deep investigation |

## Output file layout

All output paths use `${HYPOTHETEST_EVIDENCE_DIR}/during/` (absolute, set
by evaluation.sh). File naming: `<variation>-<repeat>-<phase>-<method>`.

```
${HYPOTHETEST_EVIDENCE_DIR}/during/
  baseline-1-load_data-use.toon         # USE time-series
  baseline-1-load_data-latency.toon     # latency time-series
  baseline-1-load_data-tsa/             # TSA text archive
  baseline-1-load_data-on_cpu/          # perf archive
  baseline-1-load_data-off_cpu/         # bpftrace archive
  baseline-1-load_data-raw/             # raw API responses (debugging)
    nodes_stats_t0.json
    nodes_stats_t10.json
    search_stats_t0.json
```

Methods that produce time-series (use, latency) write TOON files.
Methods that produce snapshots (tsa, on_cpu, off_cpu) write directories
of archived text/data files. Raw API responses are always archived
regardless of method.
