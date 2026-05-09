---
name: force-merge-storage-comparison
owner: storage
---

# 1. Observation

Force merge is storage intensive, and local compose evaluations can use either Docker named volumes or bind mounts. The selected storage mode may change merge duration, disk write behavior, and resulting segment/store metrics.

# 2. Question

How long does force merge take on the same data with different storage settings?

# 3. Hypothesis

Bind-mounted Elasticsearch data will produce different force-merge duration and disk write behavior than a Docker named volume for the same dataset and index settings.

```yaml
claim: bind_mount changes force_merge_duration or disk_write_bytes compared with named_volume
null: bind_mount force_merge_duration and disk_write_bytes are not materially different from named_volume
alternative: bind_mount force_merge_duration or disk_write_bytes differ materially from named_volume
tail: two_tailed
```

# 4. Variables

```yaml
baseline: named_volume
candidates:
  - bind_mount
changed:
  - compose_storage_mode
controls:
  - elasticsearch_version
  - heap_size
  - dataset
  - index_settings
  - compose_engine
```

# 5. Experiment Design

```yaml
deployment:
  target: compose
  engine: auto
  elasticsearch:
    version: 8.18.0
    security: false
    heap: 2g
    memory: 4g
dataset:
  loader: espipe
  input: ./data/logs.ndjson
  target: logs-benchmark-default
  settings:
    number_of_shards: 1
    number_of_replicas: 0
variations:
  named_volume:
    config:
      compose:
        storage:
          type: named_volume
  bind_mount:
    config:
      compose:
        storage:
          type: bind_mount
          path: ./var/esdata
evaluation:
  repeats: 3
  order: randomized
  reset:
    - delete_indices
    - delete_volumes
    - reload_dataset
  phases:
    - name: force_merge
      tool: elasticsearch_api
      with:
        method: POST
        path: /logs-benchmark-default/_forcemerge?max_num_segments=1&wait_for_completion=true
```

# 6. Measurement Plan

```yaml
measure:
  primary:
    - force_merge_duration
    - disk_write_bytes
    - cpu_percent
    - merge_time
    - resulting_segment_count
    - resulting_store_size
  secondary:
    - heap_used_percent
    - gc_time
    - disk_read_bytes
  diagnostics:
    tool: esdiag
    at:
      before_phase:
        required_apis:
          - _cluster/health
          - _nodes/stats
      after_phase:
        required_apis:
          - _nodes/stats
          - _stats
          - _cat/segments?format=json
compare:
  baseline: named_volume
  candidates:
    - bind_mount
  changed:
    - compose_storage_mode
  controls:
    - elasticsearch_version
    - heap_size
    - dataset
    - index_settings
    - compose_engine
  analysis:
    method: bootstrap
    tail: two_tailed
    alpha: 0.05
    confidence: 0.95
    effect:
      force_merge_duration: 10%
      disk_write_bytes: 10%
    assumptions:
      - delete_volumes and reload_dataset reset storage state between variations
      - force merge timings may be non-normal
    multiple_comparisons: false
  decision: Accept the hypothesis if bind_mount differs from named_volume in force_merge_duration or disk_write_bytes by at least 10% across repeats.
```

# 7. Interpretation

If bind mounts differ materially from named volumes, storage mode should be treated as a controlled variable in local force-merge benchmarks. If the difference is below the decision threshold, either storage mode is acceptable for this workload. Conclusions are limited to local compose, the selected compose engine, Elasticsearch 8.18.0, and this dataset.
