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
"null": no variation achieves more than 10% smaller store size than standard after force-merge
alternative: at least one variation achieves more than 10% smaller store size than standard after force-merge
tail: one_tailed
```

# 4. Variables

```yaml
baseline: standard
candidates:
  - logsdb
  - standard_best_compression
  - standard_best_compression_sorted
independent:
  - index_mode
  - codec
  - index_sorting
dependent:
  - store_size_after_load
  - store_size_after_force_merge
  - indexing_throughput_docs_per_sec
secondary_dependent:
  - segment_count_after_load
  - segment_count_after_force_merge
  - force_merge_duration_sec
controlled:
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
    workdir: /tmp/hypothetest/runs

dataset:
  loader: espipe
  input: datasets/yelp/yelp_academic_dataset_review.json
  options:
    batch_size: 5000
  fixture:
    mode: dynamic
    description: >
      Yelp Academic Dataset review corpus (NDJSON). Must be present at the
      declared path on the remote host before execution. The Coordinator
      must verify the file exists and is readable before the Operator runs.

setup: []

variations:
  standard:
    description: Default index mode, LZ4 codec, no index sorting.
    load_config:
      template: templates/base-template.yml
      template_name: yelp-reviews-standard

  logsdb:
    description: >
      logsdb index mode with synthetic _source, LZ4 codec. Uses the
      yelp-reviews-logsdb index template and the yelp-reviews-date-to-timestamp
      ingest pipeline to rename the corpus `date` field to `@timestamp`
      as required by logsdb.
    load_config:
      template: templates/logsdb-template.yml
      template_name: yelp-reviews-logsdb
      pipeline: templates/pipeline-date-to-timestamp.yml
      pipeline_name: yelp-reviews-date-to-timestamp

  standard_best_compression:
    description: Standard index mode with ZSTD (best_compression) codec.
    load_config:
      template: templates/standard-best-compression-template.yml
      template_name: yelp-reviews-standard-best-compression

  standard_best_compression_sorted:
    description: >
      Standard index mode with ZSTD codec and index sorting by business_id
      ascending. Sorting by a high-cardinality keyword field improves
      compression locality by co-locating documents with the same business.
    load_config:
      template: templates/standard-best-compression-sorted-template.yml
      template_name: yelp-reviews-standard-best-compression-sorted

benchmark:
  repeats: 3
  randomize_variation_order: true
  phases:
    - name: load_data
      runner: espipe
      config:
        input: datasets/yelp/yelp_academic_dataset_review.json
        target: http://ironhide.local:9200/benchmark-index
        batch_size: 5000
        # --template and --template-name resolved per variation from load_config.
        # logsdb additionally passes --pipeline and --pipeline-name.

    - name: collect_store_after_load
      runner: elasticsearch_api
      config:
        request:
          method: GET
          path: /benchmark-index/_stats/store,segments
        artifact: store_after_load.json

    - name: force_merge
      runner: elasticsearch_api
      config:
        request:
          method: POST
          path: /benchmark-index/_forcemerge?max_num_segments=1&wait_for_completion=true
        artifact: force_merge_result.json

    - name: collect_store_after_force_merge
      runner: elasticsearch_api
      config:
        request:
          method: GET
          path: /benchmark-index/_stats/store,segments
        artifact: store_after_force_merge.json

isolation:
  mode: reset_between_variations
  reset:
    - delete_indices
    - clear_caches
    - reload_dataset
    - verify_cluster_green
```

# 6. Measurement Plan

```yaml
metrics:
  primary:
    - name: store_size_after_force_merge
      unit: bytes
      source: elasticsearch_api
      api: /benchmark-index/_stats/store
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
      api: /benchmark-index/_stats/store
      field: _all.total.store.size_in_bytes
      phase: collect_store_after_load

    - name: segment_count_after_load
      unit: count
      source: elasticsearch_api
      api: /benchmark-index/_stats/segments
      field: _all.total.segments.count
      phase: collect_store_after_load

    - name: segment_count_after_force_merge
      unit: count
      source: elasticsearch_api
      api: /benchmark-index/_stats/segments
      field: _all.total.segments.count
      phase: collect_store_after_force_merge

    - name: force_merge_duration_sec
      unit: seconds
      source: phase_artifact
      artifact: force_merge_result.json
      field: took
      phase: force_merge

diagnostics:
  collector: esdiag
  collections:
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

comparison:
  baseline: standard
  candidates:
    - logsdb
    - standard_best_compression
    - standard_best_compression_sorted
  statistical_plan:
    test: bootstrap
    tail: one_tailed
    significance_level: 0.05
    confidence_level: 0.95
    minimum_effect_size:
      store_size_after_force_merge: 10%
      indexing_throughput_docs_per_sec: 20%
    assumptions:
      - variation resets (delete_indices + clear_caches + reload_dataset) make repeated measurements sufficiently independent
      - store size measurements are deterministic for the same dataset and settings; variance across repeats reflects JVM and OS caching noise
      - indexing throughput may vary due to remote host load; three repeats are exploratory
    multiple_comparison_correction: bonferroni
    multiple_comparison_note: >
      Three candidates are tested against one baseline on two primary metrics.
      Bonferroni correction is applied to the family of store_size comparisons.
      Throughput comparisons are treated as secondary and exploratory.
  decision_rule: >
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
- **Deployment**: single-node Elasticsearch running in Podman on a remote host (`ironhide.local`) via compose. Results are development-grade and should not be used to make production capacity decisions without re-running on representative hardware.
- **Elasticsearch version**: 9.3.3.
- **Index sorting caveat**: `index.sort.field: business_id` requires that documents contain a `business_id` keyword field. The Yelp review corpus includes this field natively. If the corpus is replaced with a different dataset, verify field presence before execution.
- **logsdb caveat**: `logsdb` mode uses synthetic `_source`. If downstream consumers rely on stored `_source` fields that are not reconstructable from doc values, this mode is not suitable regardless of storage savings.
- **Interpretation limit**: a >10% storage reduction is the declared practical threshold. Smaller reductions are not operationally meaningful for this experiment.
