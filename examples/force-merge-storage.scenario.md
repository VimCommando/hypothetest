---
name: force-merge-storage-comparison
owner: storage
---

# Question

How long does force merge take on the same data with different storage settings?

# Deployment

```yaml
target: compose
engine: auto
elasticsearch:
  version: 8.18.0
  security: false
  heap: 2g
  memory: 4g
```

# Dataset

```yaml
loader: espipe
input: ./data/logs.ndjson
target: logs-benchmark-default
default_settings:
  number_of_shards: 1
  number_of_replicas: 0
```

# Variations

```yaml
named_volume:
  compose:
    storage:
      type: named_volume

bind_mount:
  compose:
    storage:
      type: bind_mount
      path: ./var/esdata
```

# Benchmark

```yaml
repeats: 3
randomize_variation_order: true
isolation:
  mode: reset_between_variations
  reset:
    - delete_indices
    - delete_volumes
    - reload_dataset
phases:
  - name: force_merge
    runner: elasticsearch_api
    config:
      method: POST
      path: /logs-benchmark-default/_forcemerge?max_num_segments=1&wait_for_completion=true
```

# Metrics

```yaml
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
```

# Comparison

```yaml
baseline: named_volume
candidates:
  - bind_mount
dimensions:
  - variation
  - repeat
```
