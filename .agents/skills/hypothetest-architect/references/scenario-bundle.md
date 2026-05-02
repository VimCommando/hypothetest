# Scenario Bundle Layout

A Hypothetest test should be shareable as one zip file. The bundle root is the scenario boundary: all relative paths in `scenario.md` and `hypothetest.yml` resolve from this directory.

## Minimum Bundle

```text
<scenario-name>/
  bundle.yml
  scenario.md
  hypothetest.yml
  README.md
```

- `bundle.yml`: machine-readable bundle manifest.
- `scenario.md`: human-authored benchmark description with YAML blocks.
- `hypothetest.yml`: canonical compiled plan.
- `README.md`: short purpose, prerequisites, expected runtime, and run command.

This minimum is enough when the dataset and workload are remote, built into Rally, or otherwise resolved by the runner.

## Portable Bundle

Use this shape when the scenario should run independently in another environment:

```text
<scenario-name>/
  bundle.yml
  scenario.md
  hypothetest.yml
  README.md
  data/
  tracks/
  templates/
  scripts/
  diagnostics/
  generated/
  checksums.yml
```

## Supported Directories

- `data/`: local input data for espipe or custom runners.
  Supported formats: `.ndjson`, `.jsonl`, `.csv`, `.tsv`, `.json.gz`, `.ndjson.gz`, `.csv.gz`, `.tsv.gz`.
- `tracks/`: repo-local Rally tracks, challenges, corpora, operations, parameter sources, and track README files.
- `templates/`: Elasticsearch component templates, index templates, mappings, settings, ingest pipelines, ILM policies, and repository definitions. Config files should be YAML/YML when authored for Hypothetest; Elasticsearch API payload fixtures may be JSON when the Elasticsearch API requires JSON.
- `scripts/`: allowlisted shell or Python scripts used by benchmark phases.
  Supported files: `.sh`, `.py`.
- `diagnostics/`: esdiag sources files and diagnostic collection plans.
  Supported files: `sources.yml`, `collections.yml`.
- `generated/`: deterministic Architect output, including compose files, runbook, metrics plan, and generated runner assets.

## Bundle Manifest

`bundle.yml` describes the zip contents and validates against `schemas/bundle.schema.yaml`.

Minimum:

```yaml
apiVersion: hypothetest.elastic/v1
kind: ScenarioBundle
metadata:
  name: frozen-no-force-merge-search-cost
spec:
  scenario: scenario.md
  plan: hypothetest.yml
  readme: README.md
```

Portable:

```yaml
apiVersion: hypothetest.elastic/v1
kind: ScenarioBundle
metadata:
  name: frozen-no-force-merge-search-cost
  owner: search-storage
spec:
  scenario: scenario.md
  plan: hypothetest.yml
  readme: README.md
  portability:
    self_contained: true
    expected_runtime: 45m
    prerequisites:
      - docker or podman
      - esrally
      - espipe
      - esdiag
  directories:
    data: data/
    tracks: tracks/
    templates: templates/
    scripts: scripts/
    diagnostics: diagnostics/
    generated: generated/
  fixtures:
    - path: data/http_logs.ndjson.gz
      type: data
      format: gz
      checksum: sha256:example
    - path: diagnostics/sources.yml
      type: esdiag_sources
      format: yml
  checksums: checksums.yml
  archive:
    format: zip
    include_runs: false
```

## Optional Runtime Output

Runtime output should not be required to execute the scenario, but may be included for review or reproduction:

```text
runs/
  <scenario>/
    <timestamp>/
      manifest.toon
      raw/
        esdiag/
          <collection-point>.zip
      metrics/
      report.md
      summary.toon
      comparison.toon
```

Raw esdiag diagnostics remain zipped esdiag bundles. Hypothetest structured run data uses TOON.

## Bundle Rules

- Prefer relative paths.
- Do not include secrets, API keys, or environment-specific credentials.
- Include `checksums.yml` for local datasets, tracks, templates, and scripts when the bundle is meant to be independently reproducible.
- Include `bundle.yml` for every bundle and validate it against `schemas/bundle.schema.yaml`.
- Keep generated compose assets deterministic for the same `hypothetest.yml`.
- Use YAML/YML for Hypothetest configuration.
- Store Hypothetest structured data as TOON.
- Preserve esdiag raw diagnostics as `.zip` bundles.
