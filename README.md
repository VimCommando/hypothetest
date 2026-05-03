# Hypothetest Codex Skills

Hypothetest is a declarative workflow for designing, evaluating, and analyzing Elasticsearch benchmark experiments. A user writes `hypothesis.md` as a seven-step hypothesis evaluation: observation, question, hypothesis, variables, experiment design, measurement plan, and interpretation. The skills compile that intent into a compact execution plan, execute the evaluation, and report the results.

This repository contains the initial Codex skill set for that workflow:

- **Architect**: turns benchmark intent or `hypothesis.md` into `hypothetest.yml` plus generated evaluation assets.
- **Operator**: executes the canonical plan as an evaluation, starting with local compose deployments using Docker or Podman.
- **Analyst**: compares evaluation artifacts across variations and emits Markdown, TOON, and chart outputs.

Configurations are YAML/YML files. Hypothetest's own structured evaluation data is stored as TOON (`.toon`), not JSON or CSV.

Elasticsearch diagnostics are collected through `esdiag`, using YAML-defined API lists for each collection point. `esdiag` keeps raw API outputs in its bundled `.zip` artifact and can also process those diagnostics directly to a results cluster for metric shipping.

The hypothesis testing structure is informed by the seven-step model and statistical-risk concepts summarized in [SixSigma.us, "Hypothesis Testing: A Comprehensive Guide with Examples and Applications"](https://www.6sigma.us/six-sigma-in-focus/hypothesis-testing/).

The human-facing process is:

```text
Observation -> Question -> Hypothesis -> Variables -> Experiment Design -> Measurement Plan -> Interpretation
```

This keeps first-time authoring simple while still requiring a falsifiable claim, baseline/candidate variations, repeats, reset behavior, metric sources, a predeclared decision rule, and interpretation limits. More rigorous hypotheses can also declare null and alternative hypotheses, confidence level, test direction, statistical assumptions, multiple-comparison handling, and practical effect thresholds.

The compiled plan schema is intentionally flat:

```yaml
name
question
hypothesis
deployment
dataset
variations
evaluation
measure
compare
report
```

In `hypothetest.yml`, `measure` and `compare` are plan sections: they declare what to collect and how to decide. In `evaluation.yml`, `measurements` and `comparisons` are result sections: they point to the artifacts produced by executing that plan.

The first execution target is `compose`; `existing` and `elastic-cloud` are planned next targets. Compose hypotheses declare `scope: local` or `scope: remote`; remote compose MVP uses SSH certificate auth from the user's `.ssh/config`, may specify `remote.user`, and requires the Coordinator to verify SSH access plus permission to execute `docker compose` or `podman compose` on the remote host.

## Blueprints

A portable test is a directory that can be zipped and evaluated elsewhere. The blueprint root is the path base for `hypothesis.md` and `hypothetest.yml`.

Minimum blueprint:

```text
<blueprint-name>/
  blueprint.yml
  hypothesis.md
  hypothetest.yml
  README.md
```

Portable blueprint:

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
  checksums.yml
```

Supported fixtures:

- `data/`: `.ndjson`, `.jsonl`, `.csv`, `.tsv`, and gzip variants.
- `tracks/`: local Rally tracks and corpora.
- `templates/`: Elasticsearch templates, mappings, settings, pipelines, policies, and repository definitions.
- `scripts/`: allowlisted `.sh` and `.py` phase runners.
- `diagnostics/`: esdiag `sources.yml` and collection plans.

Datasets are declared once in `blueprint.yml`. Use `path` when the data is included or expected to already exist; use `generated_by` when the Operator should generate it during execution.

Evaluation outputs may include `evaluations/`, `evaluation.yml`, `manifest.toon`, `summary.toon`, `comparison.toon`, `report.md`, charts, and raw esdiag `.zip` bundles. An evaluation is the complete output of executing a Hypothetest plan: preserved evidence, diagnostics, measurements, comparisons, generated artifacts, and the final report. `evaluation.yml` is the schema-valid index for those artifacts; `manifest.toon` is the compact runtime manifest.

`blueprint.yml` is the machine-readable manifest for the zip contents and validates against the Architect-owned blueprint schema. It uses the same flat style as `hypothetest.yml`: `name`, `hypothesis`, `plan`, `readme`, `prerequisites`, `include`, `datasets`, and `archive`.

## Schema Ownership

The repo-root `schemas/` directory is the development mirror. Distributable
skills must carry the schemas they own so sandboxed skill environments do not
depend on arbitrary repo-root file access:

- Coordinator owns the plan contract: `.agents/skills/hypothetest-coordinator/schemas/hypothetest.schema.yaml`.
- Architect owns the blueprint contract: `.agents/skills/hypothetest-architect/schemas/blueprint.schema.yaml`.
- Operator owns the evaluation contract: `.agents/skills/hypothetest-operator/schemas/evaluation.schema.yaml`.

Downstream skills should read the producing skill's bundled schema when
cross-skill references are available. For example, the Analyst consumes
evaluations using the Operator skill's `schemas/evaluation.schema.yaml`.

## Tooling

Hypothetest tooling prefers the Rust ecosystem. Install Rust/Cargo before setup, then install the YAML schema validator with:

```bash
cargo install yaml-schema
```

The package installs the `ys` executable. In this repository, use the repo-root
development schema mirrors for validation:

```bash
ys -f schemas/blueprint.schema.yaml <blueprint>/blueprint.yml
ys -f schemas/hypothetest.schema.yaml <blueprint>/hypothetest.yml
ys -f schemas/evaluation.schema.yaml evaluations/<hypothesis>/<timestamp>/evaluation.yml
```

Install as repo-scoped skills by copying `.agents/skills` into the root of your target repository.

```bash
cp -R .agents /path/to/repo/
```

Skills:

- `$hypothetest-architect` — consults on or compiles benchmark hypotheses into a canonical plan.
- `$hypothetest-operator` — implements and evaluates the plan, initially targeting compose with Docker or Podman.
- `$hypothetest-analyst` — interprets evaluation artifacts and writes comparison reports.
