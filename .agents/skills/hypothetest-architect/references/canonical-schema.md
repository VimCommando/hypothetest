# Canonical Hypothetest YAML

```yaml
apiVersion: hypothetest.elastic/v1
kind: BenchmarkScenario
metadata:
  name: example
spec:
  question: string
  deployment:
    target: compose
    engine: auto
  dataset:
    loader: espipe
    target: benchmark-index
  setup: []
  variations:
    baseline: {}
    candidate: {}
  benchmark:
    repeats: 3
    randomize_variation_order: true
    phases:
      - name: measured_phase
        runner: rally
        config: {}
  isolation:
    mode: reset_between_variations
    reset:
      - delete_indices
      - clear_caches
      - reload_dataset
      - verify_cluster_green
  metrics:
    primary: []
    secondary: []
  diagnostics:
    collector: esdiag
    results:
      target: optional-results-cluster
    collections:
      before_phase:
        apis:
          - _cluster/health
          - _nodes/stats
  comparison:
    hypothesis:
      null: string
      alternative: string
      tail: one_tailed
    baseline: baseline
    candidates: [candidate]
    independent: []
    dependent: []
    controlled: []
    dimensions: []
    statistical_plan:
      test: bootstrap
      tail: one_tailed
      significance_level: 0.05
      confidence_level: 0.95
      minimum_effect_size: {}
      assumptions: []
      multiple_comparison_correction: false
    decision_rule: string
  report:
    formats: [markdown, toon, charts]
    interpretation: string
```
