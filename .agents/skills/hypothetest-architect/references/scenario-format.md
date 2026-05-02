# Scenario Markdown Format

A scenario is a human-readable Markdown file with YAML blocks for machine-readable sections.

Required sections:

```markdown
---
name: my-benchmark
owner: optional-owner
---

# Question

What do we want to learn?

# Deployment

```yaml
target: compose
engine: auto
```

# Dataset

```yaml
loader: espipe
input: ./data/docs.ndjson
target: benchmark-index
```

# Variations

```yaml
baseline:
  settings: {}
candidate:
  settings: {}
```

# Benchmark

```yaml
repeats: 3
phases:
  - name: measured_phase
    runner: rally
    config:
      track: ./tracks/search
      challenge: default
```

# Metrics

```yaml
primary:
  - latency_p99
```

# Comparison

```yaml
baseline: baseline
candidates:
  - candidate
```
```

The architect compiles this into `hypothetest.yml`.
