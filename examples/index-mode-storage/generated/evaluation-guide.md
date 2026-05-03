# Operator Evaluation Guide — index-mode-storage

**Blueprint**: `blueprints/index-mode-storage/`
**Grade**: Development-grade (remote compose, single-node)
**Estimated runtime**: ~60 minutes (3 repeats × 4 variations × ~5 min/repeat)

---

## Prerequisites

Before evaluating this benchmark, verify:

- [ ] Podman is installed and available on the remote host (`ironhide.local`)
- [ ] SSH certificate access to `ironhide.local` is configured in `~/.ssh/config`
- [ ] The remote user (`benchmark`) has permission to execute `podman` and `podman compose`
- [ ] `espipe` >= 0.3.0 is installed and on PATH on the machine executing the Operator
- [ ] `esdiag` is installed and on PATH on the machine executing the Operator
- [ ] The Yelp review corpus exists on the remote host at:
       `datasets/yelp/yelp_academic_dataset_review.json`
      (relative to the Operator workdir `/tmp/hypothetest/evaluations`)
- [ ] The Yelp review documents contain a `business_id` keyword field (required for
      `standard_best_compression_sorted`). This field is present natively in the
      Yelp Academic Dataset.

Execute the Coordinator readiness check before proceeding:

```sh
hypothetest coordinator check --blueprint blueprints/index-mode-storage/
```

---

## Variations

| Key | Index Mode | Codec | Sort |
|-----|-----------|-------|------|
| `standard` | standard | LZ4 (default) | none |
| `logsdb` | logsdb | LZ4 (default) | none |
| `standard_best_compression` | standard | best_compression | none |
| `standard_best_compression_sorted` | standard | best_compression | `business_id` asc |

**Baseline**: `standard`

---

## Setup (once per evaluation, before any variation)

There is no separate setup phase. `setup: []` in `hypothetest.yml`.

Index templates and ingest pipelines are applied by `espipe` at load time via
`--template`, `--template-name`, `--pipeline`, and `--pipeline-name` flags.
espipe uploads the template/pipeline to Elasticsearch before sending bulk
documents. No manual `curl` setup is required.

---

## Execution Steps (per variation, per repeat)

The Operator evaluates each variation in randomized order, 3 times total.

### 1. Reset

```sh
# Delete the benchmark index if it exists
curl -X DELETE http://ironhide.local:9200/benchmark-index

# Clear all caches
curl -X POST http://ironhide.local:9200/_cache/clear

# Verify cluster is green
curl http://ironhide.local:9200/_cluster/health?wait_for_status=green&timeout=30s
```

### 2. Load data

`espipe` applies the index template (and ingest pipeline for `logsdb`) at load
time via `--template`, `--template-name`, `--pipeline`, and `--pipeline-name`.
The index is created automatically on first bulk write.

**standard**:
```sh
espipe \
  datasets/yelp/yelp_academic_dataset_review.json \
  http://ironhide.local:9200/benchmark-index \
  --template templates/base-template.yml \
  --template-name yelp-reviews-standard \
  --batch-size 5000
```

**logsdb**:
```sh
espipe \
  datasets/yelp/yelp_academic_dataset_review.json \
  http://ironhide.local:9200/benchmark-index \
  --template templates/logsdb-template.yml \
  --template-name yelp-reviews-logsdb \
  --pipeline templates/pipeline-date-to-timestamp.yml \
  --pipeline-name yelp-reviews-date-to-timestamp \
  --batch-size 5000
```

**standard_best_compression**:
```sh
espipe \
  datasets/yelp/yelp_academic_dataset_review.json \
  http://ironhide.local:9200/benchmark-index \
  --template templates/standard-best-compression-template.yml \
  --template-name yelp-reviews-standard-best-compression \
  --batch-size 5000
```

**standard_best_compression_sorted**:
```sh
espipe \
  datasets/yelp/yelp_academic_dataset_review.json \
  http://ironhide.local:9200/benchmark-index \
  --template templates/standard-best-compression-sorted-template.yml \
  --template-name yelp-reviews-standard-best-compression-sorted \
  --batch-size 5000
```

### 3. Collect diagnostics: before_load

```sh
esdiag collect \
  --host http://ironhide.local:9200 \
  --apis "_cluster/health,_nodes/stats,_cat/nodes?v&format=json" \
  --output evaluations/index-mode-storage/<timestamp>/<variation>/<repeat>/esdiag/before_load.zip
```

### 4. Collect diagnostics: after_load

```sh
esdiag collect \
  --host http://ironhide.local:9200 \
  --apis "_nodes/stats,_stats,_cat/segments?format=json,_cat/indices?v&format=json" \
  --output evaluations/index-mode-storage/<timestamp>/<variation>/<repeat>/esdiag/after_load.zip
```

### 5. Collect store stats after load

```sh
curl http://ironhide.local:9200/benchmark-index/_stats/store,segments \
  > evaluations/index-mode-storage/<timestamp>/<variation>/<repeat>/store_after_load.json
```

### 6. Force-merge to 1 segment

```sh
curl -X POST \
  "http://ironhide.local:9200/benchmark-index/_forcemerge?max_num_segments=1&wait_for_completion=true" \
  > evaluations/index-mode-storage/<timestamp>/<variation>/<repeat>/force_merge_result.json
```

### 7. Collect store stats after force-merge

```sh
curl http://ironhide.local:9200/benchmark-index/_stats/store,segments \
  > evaluations/index-mode-storage/<timestamp>/<variation>/<repeat>/store_after_force_merge.json
```

### 8. Collect diagnostics: after_force_merge

```sh
esdiag collect \
  --host http://ironhide.local:9200 \
  --apis "_nodes/stats,_stats,_cat/segments?format=json,_cat/indices?v&format=json" \
  --output evaluations/index-mode-storage/<timestamp>/<variation>/<repeat>/esdiag/after_force_merge.zip
```

---

## Starting and Stopping Elasticsearch

```sh
# Start
podman compose -f generated/compose/compose.yml --env-file generated/compose/.env up -d

# Wait for green
curl -s http://ironhide.local:9200/_cluster/health?wait_for_status=green&timeout=60s

# Stop and remove volumes (between full variation evaluations if needed)
podman compose -f generated/compose/compose.yml down -v
```

---

## Evaluation Artifact Layout

```text
evaluations/
  index-mode-storage/
    <timestamp>/
      evaluation.yml
      manifest.toon
      standard/
        1/
          espipe_output.json
          store_after_load.json
          force_merge_result.json
          store_after_force_merge.json
          esdiag/
            before_load.zip
            after_load.zip
            after_force_merge.zip
        2/
        3/
      logsdb/
        1/ 2/ 3/
      standard_best_compression/
        1/ 2/ 3/
      standard_best_compression_sorted/
        1/ 2/ 3/
```

---

## Known Issues and Caveats

1. **business_id field**: `standard_best_compression_sorted` sorts by `business_id`.
   This field is present natively in the Yelp Academic Dataset review corpus.
   If the corpus is replaced, verify field presence before execution.

2. **espipe output format**: If espipe does not emit structured JSON,
   `indexing_throughput_docs_per_sec` must be parsed from stdout manually.
   Record the value in `espipe_output.json` as `{"docs_per_second": <value>}`.

3. **logsdb synthetic _source**: `logsdb` mode reconstructs `_source` from
   doc values. If the Yelp corpus has fields that are not stored as doc values,
   those fields will not be retrievable. This does not affect the storage
   measurement but is a production consideration.

4. **Development-grade results**: This benchmark evaluates on a single-node Podman
   cluster on a remote host. Results should not be used for production capacity
   planning without re-evaluating on representative hardware.

5. **Force-merge duration**: The `took` field in the `_forcemerge` response is
   in milliseconds. Convert to seconds when reporting.
