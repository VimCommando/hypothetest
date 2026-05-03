---
name: frozen-no-force-merge-search-cost
owner: search-storage
---

# 1. Observation

Searchable snapshot search on frozen data can be sensitive to segment shape. Force-merged snapshots should have fewer segments, while non-force-merged snapshots may cause more repository reads and cache misses.

# 2. Question

How much slower is search on frozen when not force merging?

# 3. Hypothesis

Not force merging before mounting a searchable snapshot will increase p99 search latency and repository bytes read compared with a force-merged snapshot of the same dataset.

```yaml
claim: not_force_merged increases p99 latency and repository bytes read compared with force_merged
null: not_force_merged p99 latency and repository bytes read are not materially higher than force_merged
alternative: not_force_merged p99 latency and repository bytes read are materially higher than force_merged
tail: one_tailed
```

# 4. Variables

```yaml
baseline: force_merged
candidates:
  - not_force_merged
changed:
  - force_merge_before_snapshot
controls:
  - elasticsearch_version
  - heap_size
  - dataset
  - query_mix
  - shard_count
  - replica_count
  - snapshot_repository
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
  services:
    kibana: false
  repositories:
    bench-repo:
      type: fs
      location: /usr/share/elasticsearch/snapshots/bench-repo
dataset:
  loader: espipe
  input: ./data/http_logs.ndjson
  target: logs-benchmark-default
  index_template: ./templates/logs.json
  settings:
    number_of_shards: 1
    number_of_replicas: 0
variations:
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
evaluation:
  repeats: 3
  order: randomized
  reset:
    - delete_indices
    - clear_caches
    - reload_dataset
    - verify_cluster_green
  phases:
    - name: cold_search
      tool: rally
      with:
        track: ./tracks/frozen-search
        challenge: cold-cache
    - name: warm_search
      tool: rally
      with:
        track: ./tracks/frozen-search
        challenge: warm-cache
```

# 6. Measurement Plan

```yaml
measure:
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
  diagnostics:
    tool: esdiag
    at:
      after_phase:
        apis:
          - _nodes/stats
          - _stats
          - _cat/segments?format=json
compare:
  baseline: force_merged
  candidates:
    - not_force_merged
  changed:
    - force_merge_before_snapshot
  controls:
    - elasticsearch_version
    - heap_size
    - dataset
    - query_mix
    - shard_count
    - replica_count
    - snapshot_repository
  analysis:
    method: bootstrap
    tail: one_tailed
    alpha: 0.05
    confidence: 0.95
    effect:
      search_latency_p99: 10%
      repository_bytes_read: 10%
    assumptions:
      - reset_between_variations makes repeats independent enough for exploratory comparison
      - latency and repository-read distributions may be skewed
    multiple_comparisons: false
  decision: Reject the hypothesis only if not_force_merged p99 latency and repository bytes read are not materially higher than force_merged across measured search phases.
```

# 7. Interpretation

If the not-force-merged candidate shows higher p99 latency and repository reads, the result supports force merging before snapshot for this workload. If not, force merge may not be justified for this dataset and query mix. Conclusions are limited to the compose deployment, Elasticsearch 8.18.0, the declared heap, this filesystem repository, and the provided frozen-search workload.
