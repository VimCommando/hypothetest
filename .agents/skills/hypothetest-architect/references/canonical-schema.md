# Canonical Hypothetest YAML

`hypothetest.yml` is a user-facing execution contract, not an internal API
dump. Keep it flat and walkable:

```yaml
name: example
owner: optional-team
question: string
hypothesis:
  claim: string
  null: string
  alternative: string
  tail: one_tailed
experiment:
  intent: compare_deployments
  constants:
    required:
      - dataset
      - workload
      - primary_metrics
      - decision_rule
    best_effort:
      - index.primary_shards
      - cluster.topology
  variables:
    - deployment
deployment:
  target: compose
  engine: auto
dataset:
  loader: espipe
  target: benchmark-index
variations:
  baseline: {}
  candidate: {}
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
      with: {}
measure:
  primary:
    - name: metric_name
      source: elasticsearch_api
      unit: bytes
      api: /index/_stats/store
      field: _all.total.store.size_in_bytes
      phase: measured_phase
      shape: scalar
      measures: what this number represents
      validity_note: what would make it misleading
    - simple_metric_name
  secondary: []
  diagnostics:
    tool: esdiag
    at:
      before_phase:
        apis:
          - _cluster/health
          - _nodes/stats
    during:
      profile: standard
compare:
  baseline: baseline
  candidates: [candidate]
  changed: []
  controls: []
  analysis:
    method: bootstrap
    tail: one_tailed
    alpha: 0.05
    confidence: 0.95
    effect: {}
    assumptions: []
    multiple_comparisons: false
  decision: string
report:
  formats: [markdown, toon, charts]
  limits: string
```

Use `experiment.intent` for what the user is trying to learn. Use
`experiment.variables` only for factors intentionally changed by the experiment.
Use `experiment.constants.required` for controls that must match exactly, and
`experiment.constants.best_effort` for controls that should be matched as
closely as the target allows. Do not put the same factor in constants and
variables.

Each entry in `constants.required`, `constants.best_effort`, and `variables` is
a factor name (string), not a key-value pair. The factor's value is declared
elsewhere in the plan (deployment, dataset, variation config). For example,
`elasticsearch_version` as a required constant means "this factor is held
fixed"; the actual version value lives in `deployment.elasticsearch.version`.

Keep `compare.changed` and `compare.controls` empty unless backward
compatibility or a downstream consumer still requires them. New plans should use
`experiment.variables` and `experiment.constants` as the source of truth. The
measured values already live under `measure`, so do not duplicate them as
dependent variables.

Plan vocabulary is imperative: `evaluation` says how to execute, `measure` says
what to collect, and `compare` says how to decide. Evaluation output vocabulary
is artifact-oriented: `evaluation.yml` records produced `measurements` and
`comparisons`.
