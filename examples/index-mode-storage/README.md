# index-mode-storage

Compares on-disk storage size and indexing throughput across four Elasticsearch index mode and codec configurations using the Yelp Academic Dataset review corpus.

## Variations

| Variation | Index Mode | Codec | Sort |
|-----------|-----------|-------|------|
| `standard` *(baseline)* | standard | LZ4 | none |
| `logsdb` | logsdb | LZ4 | none |
| `standard_best_compression` | standard | best_compression | none |
| `standard_best_compression_sorted` | standard | best_compression | `business_id` asc |

## Decision Rule

Accept a candidate if its post-force-merge store size is **>10% smaller** than `standard` (Bonferroni-adjusted α = 0.0167) and indexing throughput is **no more than 20% lower** than `standard`.

## Prerequisites

- Podman on the remote host (`ironhide.local` in `~/.ssh/config`)
- SSH certificate access to the remote host
- `espipe` >= 0.3.0 and `esdiag` on PATH
- Yelp review corpus at `datasets/yelp/yelp_academic_dataset_review.json` on the remote host

## Evaluation

```sh
# Verify readiness first
hypothetest coordinator check --blueprint blueprints/index-mode-storage/

# Then execute the evaluation
hypothetest operator evaluation --blueprint blueprints/index-mode-storage/
```

See `generated/scripts/evaluation.sh` for the full evaluation sequence.

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

~60 minutes (3 repeats × 4 variations)

## Grade

Development-grade (remote compose, single-node). Not suitable for production capacity planning.
