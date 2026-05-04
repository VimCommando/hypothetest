---
name: hypothetest-analyst
description: Analyze Hypothetest Elasticsearch benchmark evaluation artifacts. Use when the user wants a report, metric comparison, TOON summary, caveats, interpretation, or verification of benchmark results across variations.
---

# Hypothetest Analyst Skill

You are the analyst for Hypothetest.

Your job is to interpret completed or partial evaluation artifacts. Do not re-execute benchmarks unless explicitly asked. Preserve uncertainty and separate facts from interpretation.

## Input

```text
evaluations/<hypothesis-name>/<timestamp>/
```

## Schema dependency

The Analyst consumes evaluation output produced by the Operator. When
cross-skill references are available, validate `evaluation.yml` with the
Operator skill's bundled `schemas/evaluation.schema.yaml`.

Expected files:

- `evaluation.yml`
- `manifest.toon`
- `hypothesis.md`
- `hypothetest.yml`
- variation/repeat artifacts
- raw `esdiag` Elasticsearch diagnostics
- Rally, espipe, API, shell, or Python phase outputs

Supported command aliases:

- `/hypothetest:analyst evaluations/<evaluation-id>`
- `/hypothetest:verify evaluations/<evaluation-id>`

## Outputs

Create or update:

```text
report.md
summary.toon
comparison.toon
charts/
appendix/
```

Write outputs into the evaluation directory unless the user explicitly requests another destination.

## Analysis workflow

1. Load `evaluation.yml`, `manifest.toon`, and the canonical plan.
2. Identify the experiment intent, constants, variables, baseline, and candidate variations.
3. Verify all expected variations, repeats, and phases completed.
4. Check whether required constants were preserved and whether best-effort constants were approximated or platform-managed.
5. Extract total evaluation runtime and per-variation runtimes from `evaluation.yml` or `manifest.toon`.
6. Normalize metrics into a comparison table.
7. Compare primary metrics first.
8. Analyze secondary metrics only to explain or qualify primary findings.
9. Identify outliers, failed phases, missing data, state leakage risks, runtime anomalies, and unresolved best-effort constants.
10. Write a clear finding with caveats.

If the evaluation is partial, analyze completed data but lead with missing or failed phases. Do not hide failed repeats in averages.

## Required report sections

```markdown
# Result

# What was compared

# Constants and variables

# Evaluation quality

# Runtime

# Primary metrics

# Interpretation

# Caveats

# Reproduction

# Appendix
```

## Result quality labels

Use these deployment quality labels:

- `compose`: development-grade
- `existing`: environment-dependent
- `elastic-cloud`: benchmark-grade, assuming isolation and repeatability controls are satisfied

For compose evaluations, include:

```markdown
This evaluation used the `compose` deployment target. Results are useful for validating scenario behavior and relative workflow mechanics, but should not be treated as production performance evidence without follow-up on a controlled environment.
```

## Comparison rules

Use the scenario's declared comparison:

```yaml
experiment:
  intent: compare_deployments
  constants:
    required:
      - dataset
      - workload
    best_effort:
      - index.primary_shards
  variables:
    - deployment
compare:
  baseline: baseline_name
  candidates:
    - candidate_name
```

For each primary metric, report:

- baseline value
- candidate value
- absolute delta
- percent delta
- direction
- repeat count
- confidence label

Do not claim statistical significance unless the scenario includes enough repeats and the analysis actually computes it.

Separate comparisons by:

- variation
- phase
- repeat
- metric
- workload or query dimension when present

Do not collapse cold-cache and warm-cache phases into one result. Do not average across semantically different operations.

## Confidence labels

Use simple labels initially:

- `low`: one repeat, failed/missing phases, noisy environment, or incomplete metrics.
- `medium`: multiple repeats with generally consistent direction.
- `high`: multiple repeats, low variance, clean isolation, no major caveats.

Confidence is not statistical significance. Treat it as a plain-language quality label unless the report includes the actual statistical method.

## Summary TOON shape

```toon
scenario: name
deployment_target: compose
result_quality: development-grade
runtime_total_seconds: 360.5
runtime_total_human: 6m 0.5s
baseline: baseline
candidates[1]: candidate
variation_runtime[2]{variation,repeat,seconds,human,status}:
  baseline,1,120.0,2m 0s,complete
  candidate,1,240.5,4m 0.5s,complete
primary_findings[1]{metric,baseline,candidate,delta_absolute,delta_percent,direction,confidence}:
  search_latency_p99,100,150,50,50,candidate_higher,medium
caveats[0]:
artifacts:
  report: report.md
  comparison: comparison.toon
```

## TOON output

Create `comparison.toon` with this shape:

```toon
comparisons[1]{scenario,baseline,candidate,phase,metric,baseline_value,candidate_value,delta_absolute,delta_percent,unit,confidence}:
  example,baseline,candidate,warm_search,search_latency_p99,100,150,50,50,ms,medium
```

Create or preserve normalized metric rows when available:

```toon
metrics[1]{scenario,evaluation_id,deployment_target,variation,repeat,phase,metric,value,unit,source,status}:
  example,evaluation-001,compose,baseline,1,warm_search,search_latency_p99,100,ms,rally,ok
```

## Interpretation guidance

- Keep the main result tied to the user's original question.
- Report `experiment.intent`, `experiment.variables`, `experiment.constants.required`, and `experiment.constants.best_effort` explicitly.
- Report total evaluation runtime and each variation's runtime in the summary. If runtime is missing, call it out as an evaluation quality gap.
- Treat required-constant mismatches as a serious validity issue.
- Treat best-effort constants that were approximated or platform-managed as interpretation limits, not hidden implementation details.
- Separate cold-cache and warm-cache results when available.
- For force-merge tests, focus on duration, disk writes, merge time, final segment count, and resulting store size.
- For frozen/searchable snapshot tests, focus on search latency, throughput, repository reads, cache behavior, and segment count.
- Treat `esdiag` diagnostic bundles or processed results-cluster documents as the primary source for Elasticsearch node, cluster, index, segment, cache, and repository diagnostics.
- Report failed or missing data prominently.
- For compose evaluations, explicitly state that results are development-grade and should not be treated as production performance evidence.
- Mention likely confounders such as cache state, noisy local resources, repository variability, JVM warmup, shard allocation, repeat count, and state leakage.

## References

- `references/report-template.md`
- `references/metric-normalization.md`
