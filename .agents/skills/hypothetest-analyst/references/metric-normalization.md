# Metric Normalization

Normalize raw run metrics to a wide TOON table. Units belong in metric column
names, while invariant sources and phases belong in metadata:

```toon
metadata:
  scenario: example
  evaluation_id: evaluation-001
  deployment_target: compose
  metric_sources:
    search_latency_p99_ms: rally
    ingest_throughput_docs_per_second: espipe
  metric_phases:
    search_latency_p99_ms: warm_search
    ingest_throughput_docs_per_second: load_data
runs[2]{variation,repeat,status,search_latency_p99_ms,ingest_throughput_docs_per_second}:
  baseline,1,ok,100,300
  candidate,1,ok,150,325
```

Use `null` for missing metrics and set the run-level status to `partial` or
`failed`. Do not add a separate unit column or repeat invariant metadata in
the run table.

## Metric identity and comparison calculations

Each metric column identifies a single source, phase, operation/query dimension when present, and unit across the evaluation. When a metric occurs in multiple phases, qualify its name, such as `cold_search_latency_p99_ms` and `warm_search_latency_p99_ms`. Qualify differing operations or sources as well. Store these mappings in metadata; never overwrite one phase's value with another.

Use `delta_absolute = candidate - baseline`. For a nonzero baseline use `delta_percent = 100 * delta_absolute / baseline`. For a zero or missing baseline, write `null` for percent delta and explain that the relative change is undefined. Preserve absolute delta when both values exist. Never average semantically different phases or operations.

Comparison rows should include:

```toon
comparisons[1]{scenario,baseline,candidate,phase,metric,baseline_value,candidate_value,delta_absolute,delta_percent,unit,confidence}:
  example,baseline,candidate,warm_search,search_latency_p99,100,150,50,50,ms,medium
```

When units are unknown, preserve the source unit and mark it in the report.

## Measurement ingestion rows

For Kibana ingestion, unpivot normalized wide runs into compact long-form
measurement rows in `dashboards/data/measurements.toon`. This is an explicit
ingestion transform, not the raw artifact shape. Keep these artifacts easy to
read and diff. These rows are ingested directly with espipe; do not expand
them into ECS field paths.

Measurement rows should include:

```toon
measurements[3]{@timestamp,evaluation,scenario,started_at,completed_at,deployment,variation,repeat,phase,metric,value,unit,source,status,artifact}:
  2026-05-06T18:42:00Z,force-merge-20260506T184200Z,force-merge,2026-05-06T18:00:00Z,2026-05-06T18:42:00Z,compose,baseline,1,warm_search,search_latency_p99,100.0,ms,rally,ok,comparison.toon
  2026-05-06T18:42:00Z,force-merge-20260506T184200Z,force-merge,2026-05-06T18:00:00Z,2026-05-06T18:42:00Z,compose,candidate,1,warm_search,search_latency_p99,150.0,ms,rally,ok,comparison.toon
  2026-05-06T18:42:00Z,force-merge-20260506T184200Z,force-merge,2026-05-06T18:00:00Z,2026-05-06T18:42:00Z,compose,candidate,1,warm_search,throughput,320.5,docs/s,rally,ok,comparison.toon
```

Comparison-aware measurement rows may add:

```toon
measurements[2]{@timestamp,evaluation,scenario,deployment,variation,repeat,phase,metric,value,unit,source,status,baseline,candidate,delta_absolute,delta_percent,confidence,artifact}:
  2026-05-06T18:42:00Z,force-merge-20260506T184200Z,force-merge,compose,candidate,1,warm_search,search_latency_p99,150.0,ms,rally,ok,baseline,candidate,50.0,50.0,medium,comparison.toon
  2026-05-06T18:42:00Z,force-merge-20260506T184200Z,force-merge,compose,candidate,1,warm_search,throughput,320.5,docs/s,rally,ok,baseline,candidate,42.5,15.3,medium,comparison.toon
```

Use `measurement-schema.md` for the shared data stream and indexed field mapping standards.
