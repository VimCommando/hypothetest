---
name: index-mode-storage
owner: storage
---

# 1. Observation

Elasticsearch offers multiple index modes — `standard` and `logsdb` — each with different storage trade-offs. The `logsdb` mode uses synthetic `_source` reconstruction to avoid storing the original source document, which should reduce on-disk size. Codec selection (`best_compression` vs the default `LZ4`) and index sorting can further reduce storage. It is unclear how much each of these knobs contributes to storage reduction in practice on a real-world document corpus, and whether the storage savings come at a meaningful cost to indexing throughput.

# 2. Question

How much does each index mode and codec/sorting combination reduce on-disk index store size compared with the `standard` default, and what is the indexing throughput cost of each variation, when loading the Yelp review dataset?

# 3. Hypothesis

`logsdb` mode will reduce index store size by more than 10% compared with `standard` mode on the Yelp review corpus. Applying `best_compression` codec to `standard` mode will also reduce store size by more than 10%. Combining `best_compression` with index sorting on `standard` mode will reduce store size by more than 10%. At least one variation will achieve >10% storage reduction without more than 20% indexing throughput degradation.

```yaml
claim: at least one candidate reduces store size by more than 10% without more than 20% indexing throughput degradation
"null": no variation achieves more than 10% smaller store size than standard after force-merge
alternative: at least one variation achieves more than 10% smaller store size than standard after force-merge
tail: one_tailed
```

# 4. Variables

```yaml
baseline: standard
candidates:
  - logsdb
  - logsdb_synthetic_source
  - standard_best_compression
  - standard_best_compression_sorted
changed:
  - index_mode
  - codec
  - index_sorting
controls:
  - elasticsearch_version
  - heap_size
  - dataset
  - document_count
  - shard_count
  - replica_count
  - bulk_batch_size
```

# 5. Experiment Design

```yaml
deployment:
  target: compose
  scope: remote
  engine: podman
  elasticsearch:
    version: 9.3.3
    security: false
    heap: 2g
    memory: 4g
  services:
    kibana: false
  remote:
    host: ironhide.local
    user: benchmark
    auth:
      method: ssh_certificate
      ssh_config_host: ironhide.local
    workdir: /tmp/hypothetest/evaluations

dataset:
  loader: espipe
  input: datasets/yelp/yelp_academic_dataset_review.json
  target: per-variation
  options:
    batch_size: 5000
  fixture:
    description: >
      Yelp Academic Dataset review corpus (NDJSON). Must be present at the
      declared path before execution. The Coordinator must verify the file
      exists and is readable before the Operator executes the evaluation.

setup: []

variations:
  standard:
    description: Default index mode, LZ4 codec, no index sorting.
    config:
      load:
        template: templates/base-template.yml
        template_name: yelp-reviews-standard

  logsdb:
    description: >
      logsdb index mode, LZ4 codec, stored _source. Uses the
      yelp-reviews-logsdb index template and the yelp-reviews-date-to-timestamp
      ingest pipeline to rename the corpus `date` field to `@timestamp`
      as required by logsdb.
    config:
      load:
        template: templates/logsdb-template.yml
        template_name: yelp-reviews-logsdb
        pipeline: templates/pipeline-date-to-timestamp.yml
        pipeline_name: yelp-reviews-date-to-timestamp

  logsdb_synthetic_source:
    description: >
      logsdb index mode with synthetic _source explicitly enabled, LZ4 codec.
      Requires an enterprise or trial license.
    config:
      load:
        template: templates/logsdb-synthetic-source-template.yml
        template_name: yelp-reviews-logsdb-synthetic-source
        pipeline: templates/pipeline-date-to-timestamp.yml
        pipeline_name: yelp-reviews-date-to-timestamp
    prerequisites:
      - enterprise_or_trial_license

  standard_best_compression:
    description: Standard index mode with ZSTD (best_compression) codec.
    config:
      load:
        template: templates/standard-best-compression-template.yml
        template_name: yelp-reviews-standard-best-compression

  standard_best_compression_sorted:
    description: >
      Standard index mode with ZSTD codec and index sorting by business_id
      ascending. Sorting by a high-cardinality keyword field improves
      compression locality by co-locating documents with the same business.
    config:
      load:
        template: templates/standard-best-compression-sorted-template.yml
        template_name: yelp-reviews-standard-best-compression-sorted

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
        input: datasets/yelp/yelp_academic_dataset_review.json
        target: http://ironhide.local:9200/{variation_index}
        batch_size: 5000

    - name: collect_store_after_load
      tool: elasticsearch_api
      with:
        request:
          method: GET
          path: /{variation_index}/_stats/store,segments
        artifact: store_after_load.json

    - name: force_merge
      tool: elasticsearch_api
      with:
        request:
          method: POST
          path: /{variation_index}/_forcemerge?max_num_segments=1&wait_for_completion=true
        artifact: force_merge_result.json

    - name: collect_store_after_force_merge
      tool: elasticsearch_api
      with:
        request:
          method: GET
          path: /{variation_index}/_stats/store,segments
        artifact: store_after_force_merge.json
```

# 6. Measurement Plan

```yaml
measure:
  primary:
    - name: store_size_after_force_merge
      unit: bytes
      source: elasticsearch_api
      api: /{variation_index}/_stats/store
      field: _all.total.store.size_in_bytes
      phase: collect_store_after_force_merge

    - name: indexing_throughput_docs_per_sec
      unit: docs/sec
      source: espipe
      field: docs_per_second
      phase: load_data

  secondary:
    - name: store_size_after_load
      unit: bytes
      source: elasticsearch_api
      api: /{variation_index}/_stats/store
      field: _all.total.store.size_in_bytes
      phase: collect_store_after_load

    - name: segment_count_after_load
      unit: count
      source: elasticsearch_api
      api: /{variation_index}/_stats/segments
      field: _all.total.segments.count
      phase: collect_store_after_load

    - name: segment_count_after_force_merge
      unit: count
      source: elasticsearch_api
      api: /{variation_index}/_stats/segments
      field: _all.total.segments.count
      phase: collect_store_after_force_merge

    - name: force_merge_duration_sec
      unit: seconds
      source: phase_artifact
      artifact: force_merge_result.json
      field: took
      phase: force_merge
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

      after_force_merge:
        apis:
          - _nodes/stats
          - _stats
          - _cat/segments?format=json
          - _cat/indices?v&format=json

compare:
  baseline: standard
  candidates:
    - logsdb
    - logsdb_synthetic_source
    - standard_best_compression
    - standard_best_compression_sorted
  changed:
    - index_mode
    - codec
    - index_sorting
  controls:
    - elasticsearch_version
    - heap_size
    - dataset
    - document_count
    - shard_count
    - replica_count
    - bulk_batch_size
  analysis:
    method: bootstrap
    tail: one_tailed
    alpha: 0.05
    confidence: 0.95
    effect:
      store_size_after_force_merge: 10%
      indexing_throughput_docs_per_sec: 20%
    assumptions:
      - variation resets (delete_indices + clear_caches + reload_dataset) make repeated measurements sufficiently independent
      - store size measurements are deterministic for the same dataset and settings; variance across repeats reflects JVM and OS caching noise
      - indexing throughput may vary due to remote host load; three repeats are exploratory
    multiple_comparisons: bonferroni
    note: >
      Four candidates are tested against one baseline on two primary metrics.
      Bonferroni correction is applied to the family of store_size comparisons.
      Throughput comparisons are treated as secondary and exploratory.
  decision: >
    Accept the alternative hypothesis for a candidate if its store_size_after_force_merge
    is more than 10% smaller than the standard baseline (after Bonferroni correction,
    adjusted alpha = 0.0167) AND its indexing_throughput_docs_per_sec is no more than
    20% lower than the standard baseline. A candidate that passes the storage threshold
    but fails the throughput threshold is flagged as a storage win with throughput cost.
```

# 7. Interpretation

Results apply only to:

- **Workload**: bulk-load of the Yelp Academic Dataset review corpus via espipe, single-shard, no replicas, no concurrent search.
- **Dataset**: Yelp review documents (text-heavy, variable-length, with a high-cardinality `business_id` keyword field). Results may not generalize to metrics, traces, or time-series data.
- **Deployment**: single-node Elasticsearch executing in Podman on a remote host (`ironhide.local`) via compose. Results are development-grade and should not be used to make production capacity decisions without re-evaluating on representative hardware.
- **Elasticsearch version**: 9.3.3.
- **Index sorting caveat**: `index.sort.field: business_id` requires that documents contain a `business_id` keyword field. The Yelp review corpus includes this field natively. If the corpus is replaced with a different dataset, verify field presence before execution.
- **logsdb caveat**: `logsdb` mode uses synthetic `_source`. If downstream consumers rely on stored `_source` fields that are not reconstructable from doc values, this mode is not suitable regardless of storage savings.
- **Interpretation limit**: a >10% storage reduction is the declared practical threshold. Smaller reductions are not operationally meaningful for this experiment.
