# Metric Normalization

Normalize metrics to TOON rows shaped like:

```toon
metrics[1]{scenario,evaluation_id,deployment_target,variation,repeat,phase,metric,value,unit,source,status}:
  example,evaluation-001,compose,baseline,1,warm_search,search_latency_p99,100,ms,rally,ok
```

Comparison rows should include:

```toon
comparisons[1]{scenario,baseline,candidate,phase,metric,baseline_value,candidate_value,delta_absolute,delta_percent,unit,confidence}:
  example,baseline,candidate,warm_search,search_latency_p99,100,150,50,50,ms,medium
```

When units are unknown, preserve the source unit and mark it in the report.

## Measurement ingestion rows

For Kibana ingestion, transform normalized metric rows into compact measurement rows in `dashboards/data/measurements.toon`. Keep these artifacts easy to read and diff. These rows are ingested directly with espipe; do not expand them into ECS field paths.

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
