# Observation Methods — Prescription Guide

During-phase observation is opt-in. When the scenario warrants it, recommend
`diagnostics.during` in the compiled plan. The user can accept, modify, or
decline.

For the full method catalog (packages, collection shapes, output formats,
interpretation patterns), see the Coordinator-hosted reference.
*(shared — Source of truth: `../../hypothetest-coordinator/references/observation-methods.md`)*

## When to recommend during-phase observation

| Scenario type | Recommend | Methods |
|---|---|---|
| Ingest throughput | yes | `use`, optionally `tsa` |
| Search latency | yes | `use`, `latency`, optionally `off_cpu` |
| Storage comparison (force-merge, codec) | maybe | `use` with profile `light` |
| CPU-bound query | yes | `use`, `on_cpu`, `tsa` |
| Short phases (<15s) | no | skip — too few samples |
| Simple A/B with clear scalar metric | no | boundary diagnostics sufficient |

## Methods (summary)

| Method | Investigates | Foundation packages |
|---|---|---|
| `use` | Resource bottlenecks (CPU, disk, memory, GC, thread pools) | `elasticsearch_api` + host tools |
| `latency` | Response time distribution shape | `elasticsearch_api`, `rally` |
| `tsa` | Thread state fractions | `elasticsearch_api` (hot_threads), `jdk_tools` |
| `on_cpu` | CPU cycle attribution | `perf` (Linux only) |
| `off_cpu` | Thread blocking attribution | `bpftrace` (Linux only) |
| `drill_down` | Root cause narrowing | Not a during-phase method — Analyst interpretation pattern only |

## Profiles

| Profile | Methods | Use when |
|---|---|---|
| `none` | -- | Explicitly disable during-phase observation |
| `light` | `use` (ES APIs only) | Latency-sensitive; minimize observer effect |
| `standard` | `use` (full) | Default recommendation |
| `comprehensive` | `use`, `tsa`, `latency`, `on_cpu` | Deep investigation |

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
available. The Coordinator generates a script scoped to what's actually there.

The Architect does not need to enumerate packages — prescribe the method and
profile, and the Coordinator will use whatever it verified. Only specify
explicit packages when the user wants to **narrow** collection (e.g., "only
ES APIs, no host tools").

| Target | Available packages | Typical profile |
|---|---|---|
| `compose/local` (Linux) | ES APIs + sysstat + procps + maybe jdk_tools | `standard` |
| `compose/local` (macOS) | ES APIs + darwin_tools (vm_stat, iostat) | `standard` |
| `compose/remote` | ES APIs + remote host tools via SSH | `standard` |
| `elastic-cloud` | ES APIs only | `light` |
| `existing` | ES APIs + host tools if user declares access | `light` or `standard` |
