# Blueprint Layout

A Hypothetest blueprint is the shareable output of the Architect. It defines
the test or benchmark evaluation well enough for another user or Operator to reproduce
it. The blueprint root is the hypothesis boundary: all relative paths in
`hypothesis.md` and `hypothetest.yml` resolve from this directory.

## Minimum Blueprint

```text
<blueprint-name>/
  blueprint.yml
  hypothesis.md
  hypothetest.yml
  README.md
```

- `blueprint.yml`: flat machine-readable manifest.
- `hypothesis.md`: human-authored seven-step hypothesis evaluation.
- `hypothetest.yml`: compiled execution plan.
- `README.md`: purpose, prerequisites, expected evaluation time, and execution command.

## Portable Blueprint

Use this shape when the benchmark should execute independently in another
environment:

```text
<blueprint-name>/
  blueprint.yml
  hypothesis.md
  hypothetest.yml
  README.md
  data/
  tracks/
  templates/
  scripts/
  diagnostics/
  generated/
    scripts/
      evaluation.sh
  checksums.yml
```

## Supported Directories

- `data/`: local input data for espipe or custom phase tools.
- `tracks/`: repo-local Rally tracks, challenges, corpora, operations, and parameter sources.
- `templates/`: Elasticsearch templates, mappings, settings, ingest pipelines, ILM policies, and repository definitions.
- `scripts/`: allowlisted user-defined scripts used by benchmark phases.
- `diagnostics/`: esdiag sources files and diagnostic collection plans.
- `generated/`: deterministic Architect output, including compose files, evaluation guide, metrics plan, and generated runner assets.
- `generated/scripts/evaluation.sh`: generated deterministic runner. It executes the compiled plan in order, uses named task functions for process control, and uses explicit parallel groups only when the plan permits concurrent work.

## Dataset Fixtures

Datasets are declared once in `blueprint.yml`. Use `path` when the data is
included or expected to already exist. Use `generated_by` when the Operator
must generate it during execution. Static and dynamic datasets use the same
dataset object so users do not have to learn separate modes.

## Blueprint Manifest

`blueprint.yml` describes the zip contents and validates against
the Architect skill's bundled `schemas/blueprint.schema.yaml`.

Minimum:

```yaml
name: frozen-no-force-merge-search-cost
hypothesis: hypothesis.md
plan: hypothetest.yml
readme: README.md
```

Portable:

```yaml
name: frozen-no-force-merge-search-cost
owner: search-storage
description: Compare frozen searchable snapshot search cost with and without force merge.
hypothesis: hypothesis.md
plan: hypothetest.yml
readme: README.md
self_contained: true
expected_runtime: 45m
prerequisites:
  - docker or podman
  - esrally
  - espipe
  - esdiag
include:
  directories:
    - data/
    - tracks/
    - templates/
    - diagnostics/
    - generated/
  files:
    - path: diagnostics/sources.yml
      kind: diagnostics
      format: yml
    - path: generated/scripts/evaluation.sh
      kind: generated
      format: sh
datasets:
  - name: docs-small
    path: data/docs.ndjson.gz
    format: ndjson.gz
    size: 100MB
    checksum: sha256:example
  - name: nginx-large
    generated_by:
      tool: rally
      params:
        track: nginx-logs
        challenge: append-no-conflicts
        target_size: 200GB
    target: nginx-logs-benchmark
    size: 200GB
checksums: checksums.yml
archive:
  format: zip
  include_evaluations: false
```

## Optional Evaluation Output

Evaluation output should not be required to execute the blueprint, but may be
included for review or reproduction:

```text
evaluations/
  <hypothesis-name>/
    <timestamp>/
      evaluation.yml
      manifest.toon
      evidence/
        raw/
        diagnostics/
          esdiag/
            <collection-point>.zip
        phase-output/
      measurements/
      comparisons/
      charts/
      report.md
      summary.toon
      comparison.toon
```

An evaluation is the complete output of executing a Hypothetest plan: preserved evidence, diagnostics, measurements, comparisons, generated artifacts, and the final report.

Raw esdiag diagnostics remain zipped esdiag bundles. Hypothetest structured evaluation data uses TOON.

## Blueprint Rules

- Prefer relative paths.
- Do not include secrets, API keys, or environment-specific credentials.
- Include a falsifiable hypothesis, controlled variables, metric sources, a decision rule, and interpretation limits before execution.
- Include `checksums.yml` for local datasets, tracks, templates, and scripts when the blueprint is meant to be independently reproducible.
- Include `blueprint.yml` for every blueprint and validate it against the Architect skill's bundled `schemas/blueprint.schema.yaml`.
- Keep generated compose assets deterministic for the same `hypothetest.yml`.
- Keep `generated/scripts/evaluation.sh` deterministic for the same `hypothetest.yml`; compile the task order into shell rather than making the script reinterpret YAML at runtime.
- Use YAML/YML for Hypothetest configuration.
- Store Hypothetest structured data as TOON.
- Preserve esdiag raw diagnostics as `.zip` bundles.
