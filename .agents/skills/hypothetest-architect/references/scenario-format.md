# Hypothesis Markdown Format

`hypothesis.md` is the human-authored source of truth for a Hypothetest
blueprint. It uses a seven-step hypothesis evaluation model so new users can
write a benchmark plan in plain language while still declaring enough structure
for a repeatable test.

The Architect compiles `hypothesis.md` into `hypothetest.yml`. Markdown prose
explains intent; YAML blocks define machine-readable execution details. Do not
silently invent missing scientific intent in compile mode.

## Seven-Step Authoring Model

Required sections:

~~~markdown
---
name: my-benchmark
owner: optional-owner
---

# 1. Observation

What behavior, pain, or performance pattern prompted the test?

# 2. Question

What benchmarkable question should this experiment answer?

# 3. Hypothesis

What falsifiable claim do we expect the test to support or reject?

Recommended:

```yaml
claim: candidate improves the primary metric compared with baseline
null: candidate is not meaningfully different from baseline
alternative: candidate improves the primary metric compared with baseline
tail: two_tailed
```

# 4. Variables

```yaml
baseline: baseline
candidates:
  - candidate
changed:
  - setting_under_test
controls:
  - elasticsearch_version
  - heap_size
  - dataset
  - query_mix
```

# 5. Experiment Design

```yaml
deployment:
  target: compose
  engine: auto
dataset:
  loader: espipe
  input: ./data/docs.ndjson
  target: benchmark-index
variations:
  baseline:
    config: {}
  candidate:
    config: {}
evaluation:
  repeats: 3
  order: randomized
  reset:
    - delete_indices
    - clear_caches
    - reload_dataset
    - verify_cluster_green
  phases:
    - name: measured_phase
      tool: rally
      with:
        track: ./tracks/search
        challenge: default
```

# 6. Measurement Plan

```yaml
measure:
  primary:
    - latency_p99
  secondary: []
  diagnostics:
    tool: esdiag
    at:
      before_phase:
        apis:
          - _cluster/health
          - _nodes/stats
      after_phase:
        apis:
          - _nodes/stats
          - _stats
compare:
  baseline: baseline
  candidates:
    - candidate
  changed:
    - setting_under_test
  controls:
    - elasticsearch_version
    - heap_size
    - dataset
  analysis:
    method: bootstrap
    tail: two_tailed
    alpha: 0.05
    confidence: 0.95
    effect: 10%
    assumptions:
      - repeated measurements are independent after variation reset
    multiple_comparisons: false
  decision: Accept the hypothesis if candidate latency_p99 is no more than 10% worse than baseline.
```

# 7. Interpretation

How should results be interpreted, including acceptance, rejection, limits, and caveats?
~~~

## Compile Mapping

- Front matter becomes top-level `name`, `owner`, `description`, and `version`.
- `# 2. Question` becomes top-level `question`.
- `# 3. Hypothesis` becomes top-level `hypothesis`.
- `# 4. Variables` validates `compare.baseline`, `compare.candidates`, `compare.changed`, and `compare.controls`.
- `# 5. Experiment Design` provides `deployment`, `dataset`, `variations`, and `evaluation`.
- `# 6. Measurement Plan` provides `measure` and `compare`.
- `# 7. Interpretation` becomes `report.limits` and must preserve applicability limits.

## Rigor Rules

- The hypothesis must be falsifiable.
- Prefer explicit null and alternative hypotheses. The null hypothesis is the default assumption to reject or fail to reject; the alternative is the claim being evaluated.
- A baseline variation must be named and must exist.
- Each candidate variation must be named and must exist.
- `changed` should name only the factors intentionally varied between baseline and candidates.
- `controls` should either appear in deployment, dataset, variation, or evaluation configuration, or be called out as assumptions.
- Benchmark phases must have `name` and `tool`; tool-specific options live under `with`.
- Repeats must be declared. Prefer at least three repeats for exploratory evaluations and more for noisy measurements.
- Variation order should be randomized unless the hypothesis gives a reason not to.
- Reset defaults to resetting between variations.
- Primary metrics must have plausible sources in Rally, espipe, phase artifacts, Elasticsearch API responses, or esdiag diagnostics.
- The decision rule must be declared before execution and should include both statistical significance and practical significance when applicable.
- Declare confidence, test method, and test direction when statistical inference will be used.
- Document assumptions such as independence, distribution shape, equal variance, and sample size requirements.
- If testing many metrics or candidates at once, declare a multiple-comparison strategy or mark the comparison exploratory.
- Interpretation must state the workload, dataset, deployment, and Elasticsearch-version limits of the conclusion.

## Statistical Guidance

Hypothetest should report benchmark results as evidence against the null
hypothesis, not as proof that the alternative hypothesis is true. A statistically
significant result is not automatically operationally important, so decision
rules should include a practical effect threshold such as "latency is no more
than 15% worse" or "disk usage is at least 40% lower."

Use one-tailed tests only when the hypothesis is directional and only one
direction would change the decision. Use two-tailed tests when either
improvement or regression matters. For Elasticsearch benchmarks, latency and
throughput samples are often skewed or autocorrelated, so non-parametric,
bootstrap, or permutation methods are usually better defaults than assuming
normality.

## Minimal Example

~~~markdown
---
name: searchable-snapshot-latency
owner: search-storage
---

# 1. Observation

Search latency appears higher after enabling searchable snapshots on warm data.

# 2. Question

Does enabling searchable snapshots increase p95 search latency compared with locally stored warm indices?

# 3. Hypothesis

Searchable snapshots will increase p95 search latency by less than 15% while reducing local disk usage by at least 40%.

```yaml
claim: searchable snapshots keep latency within 15% while reducing local disk by at least 40%
null: searchable_snapshot p95 latency is more than 15% worse than local_warm, or local disk usage is less than 40% lower
alternative: searchable_snapshot p95 latency is no more than 15% worse than local_warm and local disk usage is at least 40% lower
tail: one_tailed
```

# 4. Variables

```yaml
baseline: local_warm
candidates:
  - searchable_snapshot
changed:
  - storage_mode
controls:
  - elasticsearch_version
  - heap_size
  - dataset
  - query_mix
  - shard_count
```

# 5. Experiment Design

```yaml
deployment:
  target: compose
  engine: auto
dataset:
  loader: rally
  track: ./tracks/logs
  challenge: default
variations:
  local_warm:
    config:
      tier: warm
  searchable_snapshot:
    setup:
      - type: snapshot
        repository: bench-repo
        snapshot: logs-snapshot
      - type: mount_searchable_snapshot
        tier: frozen
evaluation:
  repeats: 5
  order: randomized
  reset:
    - delete_indices
    - clear_caches
    - reload_dataset
    - verify_cluster_green
  phases:
    - name: measured_search
      tool: rally
      with:
        track: ./tracks/search
        challenge: default
```

# 6. Measurement Plan

```yaml
measure:
  primary:
    - search_latency_p95
    - local_disk_usage
  secondary:
    - throughput
  diagnostics:
    tool: esdiag
    at:
      after_phase:
        apis:
          - _nodes/stats
          - _stats
compare:
  baseline: local_warm
  candidates:
    - searchable_snapshot
  changed:
    - storage_mode
  controls:
    - elasticsearch_version
    - heap_size
    - dataset
    - query_mix
  analysis:
    method: bootstrap
    tail: one_tailed
    alpha: 0.05
    confidence: 0.95
    effect:
      search_latency_p95: 15%
      local_disk_usage: 40%
    assumptions:
      - variation resets make repeated measurements independent enough for comparison
      - latency distributions may be skewed
    multiple_comparisons: false
  decision: Accept if p95 latency is <= 15% worse and local disk usage is >= 40% lower.
```

# 7. Interpretation

If the decision rule passes, searchable snapshots are acceptable for this
workload. If latency exceeds the threshold, reject the hypothesis for this
workload. Results apply only to this dataset, query mix, hardware profile, and
Elasticsearch version.
~~~
