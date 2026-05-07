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

## Workflow

```sh
# Optional: provision a local k3s cluster
bash generated/scripts/k3s-install.sh

# Deploy Elasticsearch via ECK (applies default-heap overlay, starts port-forward)
bash generated/scripts/eck-up.sh

# Run the evaluation (2 variations x 3 repeats, randomized)
# Applies kustomize overlays between variations, waits for cluster health
bash generated/scripts/evaluation.sh run

# Dry-run to preview the plan without executing
bash generated/scripts/evaluation.sh plan

# After evaluation, tear down
bash generated/scripts/eck-down.sh

# Optional: remove k3s
bash generated/scripts/k3s-uninstall.sh
```

The evaluation runner applies `kubectl apply -k generated/eck/overlays/<variation>` before each variation's repeats, then waits for the cluster to reach green health before proceeding. Artifacts are captured per variation/repeat.

## Files

```
blueprint.yml                    — blueprint manifest
hypothesis.md                    — seven-step hypothesis
hypothetest.yml                  — canonical execution plan
generated/
  eck/
    base/
      kustomization.yaml         — kustomize base resources
      namespace.yaml             — Kubernetes namespace
      elasticsearch.yaml         — Elasticsearch CRD (baseline config)
    overlays/
      default-heap/
        kustomization.yaml       — references base (no patches)
      larger-heap/
        kustomization.yaml       — references base + patch
        patch.yaml               — heap 4g, memory 8Gi
  scripts/
    k3s-install.sh               — provision local k3s cluster
    k3s-uninstall.sh             — remove k3s
    eck-up.sh                    — deploy ECK operator + Elasticsearch
    eck-down.sh                  — tear down Elasticsearch + operator
    evaluation.sh                — evaluation runner (variation cycling + artifact capture)
```

## Evaluation Output

After `evaluation.sh run`, artifacts are written to `evaluations/<run-id>/`:

```
evaluation.yml                   — schema-valid evaluation index
evaluation.env                   — resolved environment
run_order.txt                    — randomized slot order
logs/                            — per-task log files
evidence/
  phase-output/<var>/<rep>/      — espipe_output.json, espipe_stderr.log, load_manifest.yml
  diagnostics/<var>/<rep>/       — esdiag bundles (before_load.zip, after_load.zip)
measurements/<var>/<rep>/        — stats_after_load.json
```

The Analyst consumes this output to normalize measurements, run comparisons, and produce the final report.

## Expected Runtime

~30 minutes (3 repeats x 2 variations, including rolling update waits)

## Grade

Development-grade (single-node ECK on k3s/lightweight Kubernetes, vm.max_map_count=1048576 via privileged initContainer). Not suitable for production capacity planning.
