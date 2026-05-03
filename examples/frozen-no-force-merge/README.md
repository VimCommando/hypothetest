# Frozen No Force Merge Search Cost

This blueprint compares frozen searchable snapshot search cost with and without force merge before snapshot creation.

## Prerequisites

- Docker or Podman
- esrally
- espipe
- esdiag
- `data/http_logs.ndjson` relative to this blueprint root
- `templates/logs.json` relative to this blueprint root
- `tracks/frozen-search` relative to this blueprint root

## Files

- `hypothesis.md`: seven-step benchmark hypothesis.
- `hypothetest.yml`: canonical compiled plan.
- `blueprint.yml`: portable blueprint manifest.

## Evaluation

Use the Hypothetest Operator from this blueprint root so relative paths resolve correctly.
