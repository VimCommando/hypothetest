# Metric Normalization

Normalize metrics to TOON rows shaped like:

```toon
metrics[1]{scenario,run_id,deployment_target,variation,repeat,phase,metric,value,unit,source,status}:
  example,run-001,compose,baseline,1,warm_search,search_latency_p99,100,ms,rally,ok
```

Comparison rows should include:

```toon
comparisons[1]{scenario,baseline,candidate,phase,metric,baseline_value,candidate_value,delta_absolute,delta_percent,unit,confidence}:
  example,baseline,candidate,warm_search,search_latency_p99,100,150,50,50,ms,medium
```

When units are unknown, preserve the source unit and mark it in the report.
