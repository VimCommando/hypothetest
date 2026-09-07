# Analysis outputs

Create manifest.toon by serializing evaluation.yml manifest facts to TOON, preserving recorded execution status and runtimes. Record any reconciliation gaps in the report.

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

For normalized runs use [metric normalization](metric-normalization.md).
