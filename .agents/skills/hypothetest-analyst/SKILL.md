---
name: hypothetest-analyst
description: Analyze Hypothetest Elasticsearch benchmark evaluation artifacts. Use when the user wants a report, metric comparison, TOON summary, caveats, interpretation, or verification of benchmark results across variations.
---

# Hypothetest Analyst Skill

You are the analyst for Hypothetest.

Your job is to interpret completed or partial evaluation artifacts. Do not re-execute benchmarks unless explicitly asked. Preserve uncertainty and separate facts from interpretation.

After the report artifacts are complete, create Kibana dashboards for the collected data when Kibana access is available. Use the Kibana dashboards skill at `/Users/reno/Development/elastic/agent-skills/skills/kibana/kibana-dashboards` for dashboard definitions, validation expectations, connection testing, and API operations.

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
dashboards/
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
11. After `report.md`, `summary.toon`, and `comparison.toon` are complete, prepare Kibana dashboard assets and deploy them when credentials are configured.

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
  dashboards: dashboards/
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

## Kibana dashboard workflow

Use the `kibana-dashboards` skill after report compilation, in this order:

1. Read `/Users/reno/Development/elastic/agent-skills/skills/kibana/kibana-dashboards/SKILL.md` before creating dashboard JSON.
2. Identify which collected evidence is already queryable in Elasticsearch:
   - Reuse `esdiag` results data streams when diagnostics were processed into a results cluster.
   - Reuse any Rally, espipe, phase-output, or custom measurement indices already declared in `evaluation.yml` or `manifest.toon`.
3. For Hypothetest measurements that are only local artifacts and not already indexed, create documents for the shared custom measurement data stream before dashboard creation.
4. Write generated dashboard definitions and ingestion assets under `dashboards/`.
5. Test Kibana connectivity with the dashboard skill's required command before creating or updating dashboards.
6. If the Kibana connection test fails, preserve the dashboard JSON and ingestion assets, explain the required environment variables in the report appendix or final response, and stop before attempting dashboard API writes.
7. If the connection test succeeds, upsert dashboards with stable IDs derived from the evaluation id or scenario name and timestamp.

Recommended dashboard outputs:

```text
dashboards/
  README.md
  hypothetest-overview.dashboard.json
  hypothetest-diagnostics.dashboard.json
  data/
    measurements.toon
  elasticsearch/
    index_template.yml
```

Prefer inline ES|QL visualization panels in dashboard definitions. Build dense operational dashboards with primary KPIs and key trends above the fold. Use descriptive chart titles, no markdown header panels, and time ranges that cover the evaluation run.

### Dashboard content

Create an overview dashboard when normalized metrics or comparisons exist:

- total runtime and per-variation runtime
- primary metric baseline/candidate comparison
- delta percent by metric, phase, and candidate
- repeat-level metric distribution
- failed, missing, or partial phase counts
- confidence and caveat summary as data tables when represented as indexed fields

Create a diagnostics dashboard when `esdiag` results data streams are available:

- cluster, node, index, shard, segment, cache, snapshot, repository, and search/indexing diagnostics relevant to the scenario
- diagnostic changes across variation, phase, repeat, and collection point
- links or fields identifying the preserved raw `esdiag` bundles

Do not duplicate `esdiag` documents into a custom Hypothetest index. Query the data streams produced by `esdiag process` directly.

### Custom evidence indexing

Only index custom Hypothetest evidence when the needed dashboard data is not already in `esdiag` results data streams or another declared Elasticsearch destination.

Use `espipe` for custom ingestion. Provide:

- an index template or composable template with correct field types for Kibana visualizations; start from `references/index_template.yml`
- a TOON measurement file derived from normalized analysis artifacts, preserving links back to source artifacts

Store custom measurement documents in this shared data stream:

```text
metrics-measurement-hypothetest
```

Never create a unique measurement data stream per evaluation. Use the document-level `evaluation` keyword for dashboard filters and cross-run comparison.

Conform custom measurement documents to `references/measurement-schema.md`. Keep local measurement artifacts compact and human-readable. Do not expand natural fields into ECS field paths:

- `@timestamp` is the measurement timestamp or best available evaluation timestamp.
- `evaluation` is the stable top-level keyword used to filter all documents from one evaluation.
- `scenario`, `deployment`, `variation`, `repeat`, and `phase` are natural benchmark dimensions.
- `metric`, `value`, `unit`, `source`, and `status` are natural metric fields.
- `baseline`, `candidate`, deltas, and confidence are natural comparison fields.
- `data_stream.*` is defined in the index template as constant keywords for the shared stream identity.

Minimum custom measurement fields:

```text
@timestamp
evaluation
scenario
started_at
completed_at
deployment
variation
repeat
phase
metric
value
unit
source
status
artifact
```

Optional comparison fields:

```text
baseline
candidate
delta_absolute
delta_percent
confidence
```

Map indexed fields consistently: identifiers and labels as `keyword`, metric values and deltas as numeric types, timestamps as `date`, and long report text or caveats as `text` plus `.keyword` only when useful for grouping. Do not flatten semantically different measurements into the same metric name without a phase or dimension field.

### Measurement transform

The Analyst is the transform boundary for custom measurement documents:

1. Read local evidence from `evaluation.yml`, `manifest.toon`, `summary.toon`, `comparison.toon`, phase outputs, Rally outputs, espipe outputs, API output, shell output, and Python output.
2. Extract source-specific facts without changing their meaning.
3. Normalize extracted values into stable metric and comparison rows using the existing `metrics[...]` and `comparisons[...]` TOON shapes.
4. Convert each normalized metric row into one compact TOON measurement row conforming to `references/measurement-schema.md`.
5. Write the rows to `dashboards/data/measurements.toon`.
6. Ingest that TOON file with espipe's native TOON input support into `metrics-measurement-hypothetest` after the template is ready.

Keep business logic in the Analyst transform. Do not add an ECS-compatibility ingest pipeline. If an evaluation needs an ingest pipeline for source-specific cleanup, keep it limited to that cleanup and do not use it to rename fields into ECS paths.

Do not transform `esdiag` documents into `metrics-measurement-hypothetest`. When `esdiag process` has shipped diagnostics to Elasticsearch, dashboards must query those `esdiag` data streams directly and use `metrics-measurement-hypothetest` only for Hypothetest run-level measurements that are not already indexed elsewhere.

Every generated measurement document must preserve:

- the evaluation filter key through top-level `evaluation`
- benchmark dimensions as compact `scenario`, `deployment`, `variation`, `repeat`, and `phase` fields
- numeric metric data as compact `metric` and `value` fields
- a source artifact path when the value came from a local artifact

Record custom ingestion decisions in `dashboards/README.md`, including the target index or data stream, template path, source TOON path, espipe command used or recommended, and whether ingestion was actually executed.

## During-phase interpretation

When `evidence/during/` contains sample TOON files, incorporate during-phase
observations into the analysis:

1. **Steady-state detection.** Were metrics stable during the phase, or still
   trending? If trending, note that the phase may not have reached steady state.

2. **Limiter identification.** When the USE method produced samples, identify
   the limiting resource per variation×phase from the USE taxonomy:
   `cpu`, `memory`, `disk_io`, `network`, `gc_pressure`, `lock_contention`,
   `thread_pool_saturation`, `merge_throttle`, `app_internal`, `unknown`.

   Evidence required: cite specific TOON field and value. Without USE data,
   limiter is `unknown`.

3. **Method-specific patterns:**
   - USE: saturated resource = limiter
   - TSA: flag any thread state >10% that isn't Execute or Idle
   - Latency: bimodal detection, p99/p50 ratio, moving modes
   - Off-CPU: dominant wait class
   - On-CPU: hot path, differential between variations

4. **Report section.** Add `## Limiting factor` after Primary metrics when
   during-phase data is present. Each variation×phase gets limiter + evidence.
   Omit this section when no during-phase data exists.

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
- `references/measurement-schema.md`
- `references/index_template.yml`
