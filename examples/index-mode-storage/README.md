# index-mode-storage

> **Status:** requires-external-dataset — Yelp review corpus must be provided before execution.

Compares on-disk storage size and indexing throughput across five Elasticsearch index mode and codec configurations using the Yelp Academic Dataset review corpus.

## Variations

| Variation | Index Mode | Codec | Sort |
|-----------|-----------|-------|------|
| `standard` *(baseline)* | standard | LZ4 | none |
| `logsdb` | logsdb | LZ4 | none |
| `logsdb_synthetic_source` | logsdb | LZ4 | none |
| `standard_best_compression` | standard | best_compression | none |
| `standard_best_compression_sorted` | standard | best_compression | `business_id` asc |

## Decision Rule

Accept a candidate if its post-force-merge store size is **>10% smaller** than `standard` (Bonferroni-adjusted α = 0.0167) and indexing throughput is **no more than 20% lower** than `standard`.

## Prerequisites

- Podman on the remote host (`ironhide.local` in `~/.ssh/config`)
- SSH certificate access to the remote host
- `espipe` >= 0.3.0 and `esdiag` on PATH
- A saved esdiag host, for example:
  `esdiag host add hypothetest-ironhide http://ironhide.local:9200 --app elasticsearch`
- Yelp review corpus at `datasets/yelp/yelp_academic_dataset_review.json` on the operator machine (the loader runs locally and pushes to the remote endpoint)

## Evaluation

```sh
# Verify readiness first
hypothetest coordinator check --blueprint examples/index-mode-storage/

# Then execute the evaluation
hypothetest operator evaluation --blueprint examples/index-mode-storage/
```

See `generated/scripts/evaluation.sh` for the full evaluation sequence.

For long macOS runs, launch through `caffeinate` so sleep/App Nap cannot kill
the runner:

```sh
nohup caffeinate -i ./generated/scripts/evaluation.sh run > /tmp/hypothetest-eval.log 2>&1 &
```

## Files

```
blueprint.yml          — blueprint manifest
hypothesis.md          — seven-step hypothesis
hypothetest.yml        — canonical execution plan
generated/
  compose/             — Podman Compose assets
  metrics-plan.yml     — metric sources and collection points
  scripts/             — evaluation, compose lifecycle, load, and reset scripts
```

## Elasticsearch Version

9.3.3

## Expected Runtime

~75 minutes (3 repeats × 5 variations)

## Grade

Development-grade (remote compose, single-node). Not suitable for production capacity planning.
