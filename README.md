# Hypothetest Codex Skills

Hypothetest is a declarative workflow for designing, running, and analyzing Elasticsearch benchmark experiments. A user describes a benchmark question, deployment, dataset, variations, phases, metrics, and comparison in Markdown; the skills compile that intent into a canonical plan, execute it, and report the results.

This repository contains the initial Codex skill set for that workflow:

- **Architect**: turns benchmark intent or `scenario.md` into `hypothetest.yml` plus generated run assets.
- **Operator**: runs the canonical plan, starting with local compose deployments using Docker or Podman.
- **Analyst**: compares run artifacts across variations and emits Markdown, TOON, and chart outputs.

Configurations are YAML/YML files. Hypothetest's own structured run data is stored as TOON (`.toon`), not JSON or CSV.

Elasticsearch diagnostics are collected through `esdiag`, using YAML-defined API lists for each collection point. `esdiag` keeps raw API outputs in its bundled `.zip` artifact and can also process those diagnostics directly to a results cluster for metric shipping.

The core schema is:

```yaml
deployment
dataset
setup
variations
benchmark
metrics
comparison
report
```

The first execution target is `compose`; `existing` and `elastic-cloud` are planned next targets.

## Scenario bundles

A portable test is a directory that can be zipped and run elsewhere. The bundle root is the path base for `scenario.md` and `hypothetest.yml`.

Minimum bundle:

```text
<scenario-name>/
  bundle.yml
  scenario.md
  hypothetest.yml
  README.md
```

Portable bundle:

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

Supported fixtures:

- `data/`: `.ndjson`, `.jsonl`, `.csv`, `.tsv`, and gzip variants.
- `tracks/`: local Rally tracks and corpora.
- `templates/`: Elasticsearch templates, mappings, settings, pipelines, policies, and repository definitions.
- `scripts/`: allowlisted `.sh` and `.py` phase runners.
- `diagnostics/`: esdiag `sources.yml` and collection plans.

Runtime outputs may include `runs/`, `manifest.toon`, `summary.toon`, `comparison.toon`, and raw esdiag `.zip` bundles.

`bundle.yml` is the machine-readable manifest for the zip contents and validates against `schemas/bundle.schema.yaml`.

Install as repo-scoped skills by copying `.agents/skills` into the root of your target repository.

```bash
cp -R .agents /path/to/repo/
```

Skills:

- `$hypothetest-architect` — consults on or compiles benchmark scenarios into a canonical plan.
- `$hypothetest-operator` — implements/runs the plan, initially targeting compose with Docker or Podman.
- `$hypothetest-analyst` — interprets run artifacts and writes comparison reports.
