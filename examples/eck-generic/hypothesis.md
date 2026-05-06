---
name: eck-generic-ingest
owner: infrastructure
---

# 1. Observation

Elasticsearch indexing throughput on Kubernetes is sensitive to JVM heap sizing. ECK-managed clusters configure heap via `ES_JAVA_OPTS` in the pod template, and container memory limits must accommodate both heap and off-heap usage. It is unclear whether doubling the JVM heap on a single-node cluster yields a meaningful throughput improvement for bulk ingest, or whether the default 2g heap is already sufficient for moderate workloads.

# 2. Question

Does increasing the JVM heap from 2g to 4g on a single-node Kubernetes Elasticsearch cluster improve bulk ingest throughput for a generic document corpus?

# 3. Hypothesis

Increasing the JVM heap from 2g to 4g will improve indexing throughput by at least 10% on a single-node ECK-managed cluster, because larger heap reduces GC pressure during bulk indexing.

```yaml
claim: increasing heap from 2g to 4g will improve indexing throughput by at least 10%
"null": larger heap does not improve indexing throughput by at least 10%
alternative: larger heap improves indexing throughput by at least 10%
tail: one_tailed
```

# 4. Variables

```yaml
baseline: default-heap
candidates:
  - larger-heap
changed:
  - jvm_heap_size
controls:
  - elasticsearch_version
  - node_count
  - dataset
  - bulk_batch_size
  - shard_count
  - replica_count
  - storage_size
best_effort:
  - kubernetes_node_resources
```

# 5. Experiment Design

```yaml
deployment:
  target: kubernetes
  namespace: hypothetest
  elasticsearch:
    version: 9.0.0
    nodes: 1
    storage: 10Gi
    security: false
    heap: 2g
    memory: 4g
  services:
    kibana: false
  kubernetes:
    operator_version: 3.3.2
    install_operator: true

dataset:
  loader: espipe
  input: ./data/docs.ndjson
  target: benchmark-index
  options:
    batch_size: 5000

variations:
  default-heap:
    description: Baseline — 2g heap, 4g container memory.
    config:
      elasticsearch:
        heap: 2g
        memory: 4g

  larger-heap:
    description: Candidate — 4g heap, 8g container memory.
    config:
      elasticsearch:
        heap: 4g
        memory: 8g

evaluation:
  repeats: 3
  order: randomized
  reset:
    - delete_indices
    - clear_caches
    - reload_dataset
    - verify_cluster_green
  phases:
    - name: load_data
      tool: espipe
      with:
        input: ./data/docs.ndjson
        target: benchmark-index
        batch_size: 5000

    - name: collect_stats_after_load
      tool: elasticsearch_api
      with:
        request:
          method: GET
          path: /benchmark-index/_stats/store,indexing,segments
        artifact: stats_after_load.json
```

# 6. Measurement Plan

```yaml
measure:
  primary:
    - name: indexing_throughput_docs_per_sec
      unit: docs/sec
      source: espipe
      field: docs_per_second
      phase: load_data

    - name: store_size_after_load
      unit: bytes
      source: elasticsearch_api
      api: /benchmark-index/_stats/store
      field: _all.total.store.size_in_bytes
      phase: collect_stats_after_load

  secondary:
    - name: segment_count_after_load
      unit: count
      source: elasticsearch_api
      api: /benchmark-index/_stats/segments
      field: _all.total.segments.count
      phase: collect_stats_after_load

    - name: indexing_time_millis
      unit: ms
      source: elasticsearch_api
      api: /benchmark-index/_stats/indexing
      field: _all.total.indexing.index_time_in_millis
      phase: collect_stats_after_load

  diagnostics:
    tool: esdiag
    at:
      before_load:
        apis:
          - _cluster/health
          - _nodes/stats
          - _cat/nodes?v&format=json
      after_load:
        apis:
          - _nodes/stats
          - _stats
          - _cat/segments?format=json
          - _cat/indices?v&format=json

compare:
  baseline: default-heap
  candidates:
    - larger-heap
  changed:
    - jvm_heap_size
  controls:
    - elasticsearch_version
    - node_count
    - dataset
    - bulk_batch_size
    - shard_count
    - replica_count
    - storage_size
  analysis:
    method: bootstrap
    tail: one_tailed
    alpha: 0.05
    confidence: 0.95
    effect:
      indexing_throughput_docs_per_sec: 10%
    assumptions:
      - variation resets make repeated measurements sufficiently independent
      - indexing throughput may vary due to Kubernetes scheduling and node resource contention
      - three repeats are exploratory
    multiple_comparisons: false
  decision: >
    Accept the alternative hypothesis if larger-heap indexing throughput
    is more than 10% higher than default-heap across repeats.
```

# 7. Interpretation

Results apply only to:

- **Workload**: bulk-load of a generic NDJSON corpus via espipe, single-shard, no replicas, no concurrent search.
- **Deployment**: single-node Elasticsearch 9.0.0 managed by ECK on Kubernetes. Development-grade: k3s or lightweight Kubernetes, `node.store.allow_mmap` disabled, no `vm.max_map_count` tuning.
- **Heap caveat**: increasing heap from 2g to 4g also requires increasing container memory limits from 4g to 8g. The comparison conflates JVM heap headroom with total available memory. A more controlled experiment would hold container memory constant, but 4g heap in a 4g container is not viable.
- **Interpretation limit**: a >10% throughput improvement is the declared practical threshold. Smaller improvements are not operationally meaningful for this experiment.
- **Generalization**: conclusions should not be used for production capacity planning without re-evaluating on representative infrastructure with production-grade `vm.max_map_count` and storage configuration.
