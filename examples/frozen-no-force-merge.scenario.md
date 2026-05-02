---
name: frozen-no-force-merge-search-cost
owner: search-storage
---

# Question

How much slower is search on frozen when not force merging?

# Deployment

```yaml
target: compose
engine: auto
elasticsearch:
  version: 8.18.0
  security: false
  heap: 2g
  memory: 4g
services:
  kibana: false
repositories:
  bench-repo:
    type: fs
    location: /usr/share/elasticsearch/snapshots/bench-repo
```

# Dataset

```yaml
loader: espipe
input: ./data/http_logs.ndjson
target: logs-benchmark-default
index_template: ./templates/logs.json
default_settings:
  number_of_shards: 1
  number_of_replicas: 0
```

# Variations

```yaml
force_merged:
  setup:
    - type: elasticsearch_api
      method: POST
      path: /logs-benchmark-default/_forcemerge?max_num_segments=1
    - type: snapshot
      repository: bench-repo
      snapshot: logs-force-merged
    - type: mount_searchable_snapshot
      tier: frozen

not_force_merged:
  setup:
    - type: snapshot
      repository: bench-repo
      snapshot: logs-not-force-merged
    - type: mount_searchable_snapshot
      tier: frozen
```

# Benchmark

```yaml
repeats: 3
randomize_variation_order: true
phases:
  - name: cold_search
    runner: rally
    config:
      track: ./tracks/frozen-search
      challenge: cold-cache
  - name: warm_search
    runner: rally
    config:
      track: ./tracks/frozen-search
      challenge: warm-cache
```

# Metrics

```yaml
primary:
  - search_latency_p50
  - search_latency_p90
  - search_latency_p99
  - throughput
  - repository_bytes_read
  - searchable_snapshot_cache_hit_rate
  - segment_count
secondary:
  - cpu_percent
  - heap_used_percent
  - gc_time
  - disk_read_bytes
  - disk_write_bytes
```

# Comparison

```yaml
baseline: force_merged
candidates:
  - not_force_merged
dimensions:
  - variation
  - phase
  - query_name
  - repeat
```
