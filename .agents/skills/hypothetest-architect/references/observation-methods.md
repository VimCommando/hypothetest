# Observation Methods

During-phase observation is opt-in. When the scenario warrants it, recommend
`diagnostics.during` in the compiled plan. The user can accept, modify, or
decline.

## When to recommend during-phase observation

| Scenario type | Recommend | Methods |
|---|---|---|
| Ingest throughput | yes | `use`, optionally `tsa` |
| Search latency | yes | `use`, `latency`, optionally `off_cpu` |
| Storage comparison (force-merge, codec) | maybe | `use` with profile `light` |
| CPU-bound query | yes | `use`, `on_cpu`, `tsa` |
| Short phases (<15s) | no | skip — too few samples |
| Simple A/B with clear scalar metric | no | boundary diagnostics sufficient |

## Methods

Each method prescribes packages, key signals, and an Analyst interpretation
pattern.

### `use` — Utilization, Saturation, Errors

Investigates resource bottlenecks. The foundation method.

- **Packages:** `elasticsearch_api`, `sysstat`, `procps`
- **Key signals:** CPU util, disk I/O util, memory pressure, thread pool queue/rejected, GC frequency
- **Analyst pattern:** saturated resource = limiter. Report per-variation×phase.
- **Limiter taxonomy:** `cpu`, `memory`, `disk_io`, `network`, `gc_pressure`, `lock_contention`, `thread_pool_saturation`, `merge_throttle`, `app_internal`, `unknown`

### `tsa` — Thread State Analysis

Investigates where thread time goes.

- **Packages:** `elasticsearch_api` (hot_threads), `jdk_tools` (jstack, jcmd)
- **Key signals:** Execute, Runnable, Sleep, Lock, Idle fractions
- **Analyst pattern:** flag any state >10% that isn't Execute or Idle

### `off_cpu` — Off-CPU Analysis

Investigates where threads block.

- **Packages:** `bpftrace`, `perf`
- **Key signals:** blocked-time stacks, I/O wait, lock wait, sleep wait
- **Analyst pattern:** identify dominant wait class, correlate with USE saturation

### `on_cpu` — On-CPU Analysis

Investigates where CPU cycles go.

- **Packages:** `perf`, `elasticsearch_api` (hot_threads)
- **Key signals:** CPU flame graph top frames, IPC, branch misses
- **Analyst pattern:** hot path identification, differential between variations

### `latency` — Response Time Analysis

Investigates response time distribution shape.

- **Packages:** `elasticsearch_api`, `rally`, `bpftrace`
- **Key signals:** p50, p90, p99, p99/p50 ratio, histogram shape
- **Analyst pattern:** bimodal detection, moving modes, outlier fraction
- **Schema effect:** auto-sets `shape: percentile_set` or `histogram` on relevant metrics

### `drill_down` — Root Cause Drill-Down

Post-analysis method. Used by the Analyst after identifying a regression, not
prescribed at compile time. Layer-by-layer investigation until root cause.

## Profiles

Named method combinations. Use as shorthand in `diagnostics.during.profile`.

| Profile | Methods | Packages | Use when |
|---|---|---|---|
| `none` | — | — | Explicitly disable during-phase observation |
| `light` | `use` (ES APIs only) | `elasticsearch_api` | Latency-sensitive; minimize observer effect |
| `standard` | `use` (full) | `elasticsearch_api`, `sysstat`, `procps` | Default recommendation |
| `comprehensive` | `use`, `tsa`, `latency`, `on_cpu` | all available | Deep investigation |

## Prescription rules

1. Never prescribe `during` without the user's scenario warranting it.
2. If the scenario has only short phases (<15s), skip during-phase — too few samples.
3. Start with `standard` unless there's a reason for more or less.
4. For latency benchmarks, add the `latency` method (promotes metrics to percentile_set).
5. For CPU investigations, add `on_cpu` and `tsa`.
6. `off_cpu`, `on_cpu`, and `tsa` (with `jdk_tools`) require Linux host tools or JVM access. Do not prescribe them for macOS or cloud targets — the Coordinator will report their packages as unavailable. Prefer `use` + `latency` on those platforms.
7. `drill_down` is not a during-phase method — it's a post-analysis Analyst pattern. Do not include it in `diagnostics.during.methods`.

## Schema shape

Option 1 — profile shorthand:
```yaml
diagnostics:
  during: standard
```

Option 2 — explicit methods:
```yaml
diagnostics:
  during:
    methods: [use, off_cpu]
```

Option 3 — profile + additional methods:
```yaml
diagnostics:
  during:
    profile: standard
    methods: [off_cpu]
```

Option 4 — full custom:
```yaml
diagnostics:
  during:
    interval: 10s
    packages:
      - name: elasticsearch_api
        apis: [_nodes/stats, _cat/thread_pool?format=json]
      - name: sysstat
    phases: [load_data]
```

## Platform-aware prescription

The Architect prescribes methods. The Coordinator discovers what packages are
available. The Operator generates a script scoped to what's actually there.

The Architect does not need to enumerate packages — prescribe the method and
profile, and the Operator will use whatever the Coordinator verified. Only
specify explicit packages when the user wants to **narrow** collection (e.g.,
"only ES APIs, no host tools").

| Target | What the Operator gets | Typical profile |
|---|---|---|
| `compose/local` (Linux) | ES APIs + sysstat + procps + maybe jdk_tools | `standard` |
| `compose/local` (macOS) | ES APIs + darwin_tools (vm_stat, iostat) | `standard` |
| `compose/remote` | ES APIs + remote host tools via SSH | `standard` |
| `elastic-cloud` | ES APIs only | `light` |
| `existing` | ES APIs + host tools if user declares access | `light` or `standard` |

For `elastic-cloud` or restricted targets, recommend profile `light` —
the Coordinator will report that only `elasticsearch_api` is verified, and
the Operator will generate accordingly.
