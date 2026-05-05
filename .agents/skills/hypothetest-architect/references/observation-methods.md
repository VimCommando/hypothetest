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
6. `drill_down` is never prescribed — it's an Analyst-time reaction.
7. `workload_characterization` is an Architect prompt (section F), not a during-phase method.

## Schema shape

```yaml
diagnostics:
  tool: esdiag
  at: { ... }          # boundary snapshots (unchanged)

  during:              # NEW — optional
    # Option 1: profile shorthand
    profile: standard

    # Option 2: explicit methods
    methods: [use, off_cpu]

    # Option 3: profile + additional methods
    profile: standard
    methods: [off_cpu]

    # Option 4: full custom
    interval: 10s
    packages:
      - name: elasticsearch_api
        apis: [_nodes/stats, _cat/thread_pool?format=json]
      - name: sysstat
    phases: [load_data]
```

## Package availability by deployment target

| Target | Available packages |
|---|---|
| `compose/local` | `elasticsearch_api`, host CLI tools (`sysstat`, `procps`, etc.) |
| `compose/remote` | `elasticsearch_api`, host CLI via SSH |
| `elastic-cloud` | `elasticsearch_api` only |
| `existing` | `elasticsearch_api`, host tools if user declares access |

When compiling for `elastic-cloud` or restricted targets, constrain to
`elasticsearch_api` package only (profile `light`).
