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
  primary: []
  secondary: []
  diagnostics:
    tool: esdiag
    at:
      before_phase:
        apis:
          - _cluster/health
          - _nodes/stats
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

Use `changed` only for the main factors under test. Use `controls` for
conditions the user intends to hold constant. The measured values already live
under `measure`, so do not duplicate them as dependent variables.

Plan vocabulary is imperative: `evaluation` says how to execute, `measure` says
what to collect, and `compare` says how to decide. Evaluation output vocabulary
is artifact-oriented: `evaluation.yml` records produced `measurements` and
`comparisons`.
