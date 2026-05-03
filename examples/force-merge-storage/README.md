# Force Merge Storage Comparison

This blueprint compares force-merge behavior between Docker named-volume and bind-mount Elasticsearch storage in a local compose deployment.

## Prerequisites

- Docker or Podman
- espipe
- esdiag
- `data/logs.ndjson` relative to this blueprint root

## Files

- `hypothesis.md`: seven-step benchmark hypothesis.
- `hypothetest.yml`: canonical compiled plan.
- `blueprint.yml`: portable blueprint manifest.

## Evaluation

Use the Hypothetest Operator from this blueprint root so relative paths resolve correctly.
