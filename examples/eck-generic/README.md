# eck-generic-ingest

Generic Kubernetes (ECK) deployment target example. Compares bulk ingest throughput between two JVM heap configurations on a single-node ECK-managed Elasticsearch cluster.

## Variations

| Variation | Heap | Memory | Description |
|-----------|------|--------|-------------|
| `default-heap` *(baseline)* | 2g | 4Gi | Architect default configuration |
| `larger-heap` | 4g | 8Gi | Doubled heap and container memory |

## Decision Rule

Accept the candidate if indexing throughput is **>10% higher** than the baseline across repeats.

## Prerequisites

- Kubernetes cluster (k3s via `k3s-install.sh` or existing)
- `kubectl` and `helm` on PATH
- `espipe` and `esdiag` on PATH
- NDJSON corpus at `data/docs.ndjson` relative to this blueprint root

## Deployment

```sh
# Optional: provision a local k3s cluster
bash generated/scripts/k3s-install.sh

# Deploy Elasticsearch via ECK
bash generated/scripts/eck-up.sh

# After evaluation, tear down
bash generated/scripts/eck-down.sh

# Optional: remove k3s
bash generated/scripts/k3s-uninstall.sh
```

## Files

```
blueprint.yml                    — blueprint manifest
hypothesis.md                    — seven-step hypothesis
hypothetest.yml                  — canonical execution plan
generated/
  eck/
    namespace.yaml               — Kubernetes namespace
    elasticsearch.yaml           — Elasticsearch CRD (baseline config)
  scripts/
    k3s-install.sh               — provision local k3s cluster
    k3s-uninstall.sh             — remove k3s
    eck-up.sh                    — deploy ECK operator + Elasticsearch
    eck-down.sh                  — tear down Elasticsearch + operator
```

## Elasticsearch Version

9.0.0

## Expected Runtime

~30 minutes (3 repeats x 2 variations)

## Grade

Development-grade (single-node ECK on k3s/lightweight Kubernetes). Not suitable for production capacity planning.
