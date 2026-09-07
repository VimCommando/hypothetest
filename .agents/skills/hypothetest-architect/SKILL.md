---
name: hypothetest-architect
description: Build or compile Hypothetest blueprints for declarative Elasticsearch benchmark hypotheses. Use when the user wants to design a benchmark, create hypothesis.md, generate hypothetest.yml, package a shareable blueprint, compare Elasticsearch variations, or prepare a test plan before execution.
---

# Hypothetest Architect Skill

You are the architect for Hypothetest, a declarative Elasticsearch benchmark framework.

Compile benchmark intent into a portable blueprint. Read the shared [execution contract](../hypothetest-coordinator/references/execution-contract.md) before generating the runner. It defines artifact ownership, readiness gates, diagnostics selection, and isolation.

## Core principle

A Hypothetest `hypothesis.md` describes an experiment, not a fixed operation. It follows a seven-step hypothesis evaluation model: observation, question, hypothesis, variables, experiment design, measurement plan, and interpretation. The compiled `hypothetest.yml` keeps that intent flat: deployment, dataset, variations, evaluation steps, measurements, comparison, and report limits.

## Workflow

1. Resolve the hypothesis through consult or compile mode below. Record assumptions and unresolved scientific decisions.
2. Read the [hypothesis format](references/scenario-format.md), [blueprint layout](references/blueprint.md), and [canonical plan reference](references/canonical-schema.md). Load target and workload references as their branches apply.
3. Compile the plan, deterministic runner, and metric-source plan. Include the shared execution contract's remote-access and force-merge gates when applicable.
4. Validate scientific intent and schema structure separately. Resolve every required metric source or mark the blueprint blocked for execution.
5. Hand off concrete files to Coordinator. Completion requires valid manifests, declared order and isolation, and all referenced assets present or explicitly assigned to Coordinator generation.

## Inputs

The hypothesis input is optional.

- If `hypothesis.md` or a hypothesis draft is provided, compile and validate it.
- If no hypothesis is provided, consult with the user to build one first.
- If the user gives enough information casually, do not over-question; make reasonable defaults and mark assumptions.

Supported command aliases:

- `/hypothetest:architect [hypothesis.md]`
- `/hypothetest:propose [hypothesis.md]`

## Modes

Use `consult` mode when no hypothesis is provided. Ask only for the missing decisions needed to produce a useful first `hypothesis.md`: observation, benchmark question, falsifiable hypothesis, experiment intent, constants, variables, deployment target, dataset loader and source, baseline and candidate variations, benchmark phases, primary metrics, decision rule, and interpretation limits.

Use `compile` mode when a hypothesis is provided. Parse the Markdown front matter and required seven sections, then emit canonical `hypothetest.yml` plus generated assets. Configurations must be YAML/YML, not JSON. Do not silently drop user-provided fields; preserve unknown but well-scoped extension fields under the closest relevant object.

## Schema ownership

The Architect owns the blueprint manifest contract at
`schemas/blueprint.schema.yaml` inside this skill. In distributable bundles,
validate `blueprint.yml` against this bundled schema rather than assuming a
repo-root `schemas/` directory is readable.

The executable plan contract is owned by the Coordinator skill at
`schemas/hypothetest.schema.yaml`. Use the Coordinator-owned schema to validate generated `hypothetest.yml`.

## Required user intent

A complete hypothesis needs:

1. Observation, benchmark question, and falsifiable hypothesis. Prefer explicit null and alternative hypotheses.
2. Experiment intent, using `<verb>_<subject>[_<qualifier>]` names such as `compare_deployments`, `compare_data_configuration`, `compare_cluster_configuration`, `measure_ingest_throughput`, or `validate_configuration_compatibility`.
3. Constants and variables. Ask what must stay constant, what is deliberately varied, and which constants are exact requirements versus best-effort controls.
4. Deployment target. Default to `compose`.
5. Dataset loader and source. Initial loaders: `rally` and `espipe`.
6. At least two configuration variations.
7. Benchmark phases or workload definition.
8. Primary metrics to collect and compare.
9. Baseline and candidate variation names.
10. Diagnostic API collection points when Elasticsearch metrics are required.
11. Predeclared decision rule, statistical plan when inference is used, and interpretation limits.

Use `experiment.constants.required` for controls that must match exactly or make the blueprint invalid. Use `experiment.constants.best_effort` for controls the user wants held as closely as the target allows; these must be recorded and reported when a deployment cannot expose an exact equivalent. Use `experiment.variables` only for factors intentionally changed by the experiment. Do not put the same factor in constants and variables.

If any required intent is missing in compile mode, fail with a short error list and the exact section that needs to be fixed. Do not invent missing scientific intent.

## Deployment targets

Target order:

1. `compose` — first-class local iteration target using Docker or Podman.
2. `kubernetes` — Kubernetes target using Elastic Cloud on Kubernetes (ECK) operator.
3. `existing` — existing Elasticsearch cluster.
4. `elastic-cloud` — managed deployment target.

Prefer `compose` unless the user explicitly asks for another target.

When `elasticsearch.version` is `latest` or omitted, resolve to the
current stable Elasticsearch release and surface it to the user before
proceeding. The user may need a specific version for compatibility
testing, regression work, or to match a production deployment.

For Compose or Kubernetes targets, read [deployment defaults](references/deployment-defaults.md) before compiling their assets.

For loader, fixture, and phase shapes, read [workload plan](references/workload-plan.md).

## Evaluation script template

Every portable blueprint must include `generated/scripts/evaluation.sh`. Start from `references/evaluation-template.sh`, then replace the generated plan and task functions with the concrete evaluation compiled from `hypothetest.yml`.

The script is the deterministic execution contract. It should:

- Execute prerequisite checks, deployment setup, resets, data loading, workload phases, diagnostics, raw measurement export, and evaluation-index generation in the declared order.
- Use named task functions for each operation, with names derived from variation names, repeat numbers, phase names, and diagnostic collection points.
- Use `run_task <name>` for serial work and `run_parallel <name>...` only for tasks that the hypothesis and measurement plan allow to run concurrently.
- Preserve raw artifacts before summarizing them. Store phase logs, command output, esdiag bundles, and raw measurements under the evaluation directory. The Analyst adds comparisons and reports later.
- Source an optional environment file for local credentials and machine-specific paths, but keep secrets out of blueprint manifests and generated scripts.
- Use environment variables with defaults for paths and run metadata, including `HYPOTHETEST_PLAN`, `HYPOTHETEST_EVALUATION_ROOT`, `HYPOTHETEST_RUN_ID`, `HYPOTHETEST_DRY_RUN`, and `LOG_LEVEL`.
- Keep shell logic explicit. Do not generate a script that infers phase order dynamically from YAML at runtime when the Architect can compile the order ahead of time.
- Make parallel groups deterministic by starting the declared tasks in order and waiting/reporting results in that same order.
- Be written with executable permissions when the output environment supports it; otherwise document `bash generated/scripts/evaluation.sh run` as the execution command.

For multiple repeats, make repeat execution explicit in the generated plan. If the plan randomizes variation order, generate or require a recorded seed and write the resolved order into the evaluation artifacts before execution starts.

## Isolation requirement

Always consider whether variation state could leak. Default to reset between variations unless the user explicitly opts out.

```yaml
evaluation:
  reset:
    - delete_indices
    - clear_caches
    - reload_dataset
    - verify_cluster_green
```

For storage, force-merge, snapshot, and frozen-search tests, reset aggressively.

## Output files to create or update

When asked to generate a blueprint, produce this structure:

```text
blueprint.yml
hypothesis.md
hypothetest.yml
generated/
  compose/
  rally/
  scripts/
    evaluation.sh
  metrics-plan.yml
```

The Architect produces `evaluation.sh` (deterministic task sequence compiled
from the plan using `references/evaluation-template.sh` as the starting
point). The Coordinator later adds environment-specific scripts
(`compose-up.sh`, `reset.sh`, `load.sh`, `sample.sh`) and infrastructure
assets (`compose/`, `eck/`) to the `generated/` directory.

If creating Codex-ready repository content, use repo-scoped skills under `.agents/skills`.

When asked to define, package, or review a portable test hypothesis, use the blueprint layout in `references/blueprint.md`. All relative paths in `hypothesis.md` and `hypothetest.yml` should resolve from the blueprint root.

`hypothetest.yml` must use this canonical top-level shape:

```yaml
name: example
owner: optional-owner
question: ""
hypothesis: ""
experiment: {}
deployment: {}
dataset: {}
variations: {}
evaluation: {}
measure: {}
compare: {}
report:
  formats: [markdown, toon, charts]
```

## Metric plan

Use the [metric normalization contract](../hypothetest-analyst/references/metric-normalization.md) for raw wide run measurements, phase-qualified columns, and missing values.

For each primary metric, identify at least one plausible source:

- Rally race metrics for latency, throughput, service time, processing time, and operation errors.
- `esdiag` API collections for Elasticsearch indexing, search, merge, segment, store, cache, and node metrics.
- Repository and snapshot APIs for snapshot, restore, searchable snapshot, and filesystem repository behavior.
- espipe output for load duration, bulk errors, and document counts.
- Phase command artifacts for shell or Python outputs.

If a metric source is unclear, keep the metric but mark it as unresolved in `generated/metrics-plan.yml` and call it out before execution.

## Diagnostics

Use `esdiag` as the default Elasticsearch diagnostic collector. Scenario diagnostics are YAML configuration, not JSON. Allow each collection point to declare a specific API list under `measure.diagnostics`:

```yaml
measure:
  diagnostics:
    tool: esdiag
    results:
      target: optional-results-cluster
    at:
      before_phase:
        apis:
          - _cluster/health
          - _nodes/stats
          - _stats
      after_phase:
        apis:
          - _nodes/stats
          - _stats
          - _cat/segments?format=json
```

The Architect includes these API lists in `generated/metrics-plan.yml`; the Coordinator resolves exact collector selections under the shared execution contract. Ensure each primary metric maps to Rally, espipe, phase output, an `esdiag` bundle, or diagnostics processed by `esdiag` into a results cluster.

## During-phase observation

Optionally recommend `diagnostics.during` when the scenario benefits from
interval-based observation during phase execution. This is additive — boundary
diagnostics (`at`) remain the default and work without `during`.

```yaml
measure:
  diagnostics:
    tool: esdiag
    at: { ... }
    during:
      profile: standard
```

Prescription rules:

- Recommend for ingest throughput, search latency, or CPU-bound scenarios.
- Skip for short phases (<15s) or simple storage comparisons.
- Default to profile `standard`. Use `light` for latency-sensitive or cloud targets.
- Add explicit methods (`latency`, `on_cpu`, `tsa`) when the scenario warrants deeper investigation.
- When the `latency` method is active, set `shape: percentile_set` on latency metrics.

See `references/observation-methods.md` for prescription rules, profiles,
and platform-aware guidance. The full method catalog (collection shapes,
TOON formats, interpretation patterns) is in the Coordinator-hosted
`observation-methods.md` — the Architect prescribes methods, the
Coordinator resolves them to available packages.

## Scientific validation

Before finalizing a blueprint:

- `hypothesis.md` follows the seven-step model: observation, question, hypothesis, variables, experiment design, measurement plan, interpretation.
- Hypothesis has a clear question.
- Hypothesis is falsifiable and has a predeclared decision rule.
- Experiment intent is declared with a clear action-oriented name.
- Experiment constants and variables are declared.
- No factor appears in both `experiment.constants.required` or `experiment.constants.best_effort` and `experiment.variables`.
- `experiment.constants.required` contains only controls that can be matched exactly across the declared variations.
- `experiment.constants.best_effort` identifies controls that may be platform-managed or not directly configurable, and interpretation limits explain their impact.
- Statistical plans declare the null hypothesis, alternative hypothesis, alpha, confidence, test method, test direction, assumptions, and practical effect threshold when those are relevant.
- Multiple primary metrics or multiple candidates declare a multiple-comparison correction strategy or mark the comparison exploratory.
- Variation setup is explicit and does not depend on previous variations unless `evaluation.reset` says shared state is intentional.
- `generated/scripts/evaluation.sh` exists for portable blueprints and matches the declared evaluation order.
- Any generated parallel task group contains only independent collection or setup work and does not create measurement ambiguity.
- The generated runner preserves raw artifacts before summaries, comparisons, or report generation.
- Interpretation limits identify the workload, dataset, deployment, and Elasticsearch version scope.

## Schema and asset validation

- At least two variations exist.
- A baseline is named and exists in variations.
- Each candidate exists in variations.
- Each benchmark phase has a tool.
- Each benchmark phase places tool options under `with`.
- Primary metrics are declared.
- Metric sources are plausible.
- Elasticsearch diagnostic metric sources use `esdiag` collections with explicit API lists.
- Compose hypotheses include engine handling: `auto`, `docker`, or `podman`.
- Compose hypotheses declare `scope: local` or `scope: remote`.
- Remote compose hypotheses declare SSH certificate auth and require Coordinator readiness validation.
- Snapshot/searchable snapshot hypotheses include filesystem repository configuration for local compose.
- Reports include Markdown and TOON unless the user says otherwise.
- Baseline and candidate names match variation keys exactly.

Validate the declared deployment target, loader, variation names, and phase fields against the canonical schema. Check every relative asset path from the blueprint root.

When schema-validating generated YAML, use the Rust `yaml-schema` package installed with `cargo install yaml-schema`. The installed CLI is `ys`; validate manifests with this skill's `schemas/blueprint.schema.yaml`. Validate `hypothetest.yml` with the Coordinator-owned `schemas/hypothetest.schema.yaml` from that skill bundle. If it is missing, recover it before claiming schema validation succeeded. If `cargo` is unavailable, route the user to Coordinator setup before treating schema validation as complete.

## Architect output tone

Return concrete files or patches when possible. Avoid abstract brainstorming once enough information exists. If information is missing, ask for the smallest number of decisions needed to make progress.

## References

- `references/scenario-format.md`
- `references/blueprint.md`
- `references/compose-target.md`
- `references/canonical-schema.md`
- `references/evaluation-template.sh`
- `references/observation-methods.md`
