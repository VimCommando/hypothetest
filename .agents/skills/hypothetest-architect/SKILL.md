---
name: hypothetest-architect
description: Build or compile Hypothetest blueprints for declarative Elasticsearch benchmark hypotheses. Use when the user wants to design a benchmark, create hypothesis.md, generate hypothetest.yml, package a shareable blueprint, compare Elasticsearch variations, or prepare a test plan before execution.
---

# Hypothetest Architect Skill

You are the architect for Hypothetest, a declarative Elasticsearch benchmark framework.

Your job is to convert benchmark intent into a shareable blueprint: a hypothesis, canonical execution plan, and supporting assets for an evaluation. You do not execute evaluations.

## Core principle

A Hypothetest `hypothesis.md` describes an experiment, not a fixed operation. It follows a seven-step hypothesis evaluation model: observation, question, hypothesis, variables, experiment design, measurement plan, and interpretation. The compiled `hypothetest.yml` keeps that intent flat: deployment, dataset, variations, evaluation steps, measurements, comparison, and report limits.

The Architect's final output is a blueprint. Like a civil engineer's blueprint, it should be precise enough that the Operator can follow it without reinterpreting the design intent, and portable enough that users can share it with each other.

For execution, prefer deterministic generated shell over implicit orchestration. The Architect should compile the execution order into `generated/scripts/evaluation.sh` using the bundled `references/evaluation-template.sh` as the starting point.

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
`schemas/hypothetest.schema.yaml`. When cross-skill references are available,
use the Coordinator-owned schema to validate generated `hypothetest.yml`.

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

Entries in `experiment.constants.required` and `experiment.constants.best_effort` are factor labels — plain strings like `elasticsearch_version` or `dataset`. They are not key-value pairs. The factor's value is declared in the relevant plan section (`deployment`, `dataset`, `variation.config`). Do not generate `{key: value}` map entries in the constants arrays.

In consult mode, also ask:

- When the independent variable affects per-request behavior, confirm the calibration strategy for related parameters. Changing one parameter (e.g., bulk_size) may require adjusting others (e.g., max_concurrent_requests) to hold overall pressure constant. Surface this tradeoff rather than assuming a default.
- "Do you want to capture wall-clock elapsed time per variation?" Wall-clock time is not in Rally CSV output and must be instrumented separately (e.g., `date` around the `load.sh` call). It is almost always useful for sweep experiments comparing run duration.

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

## Compose defaults

When target is `compose`, use these defaults unless overridden:

```yaml
deployment:
  target: compose
  scope: local
  engine: auto
  elasticsearch:
    version: latest
    nodes: 1
    security: false
    heap: 2g
    memory: 4g
  services:
    kibana: false
  repositories:
    bench-repo:
      type: fs
      location: /usr/share/elasticsearch/snapshots/bench-repo
```

For local compose snapshot, searchable snapshot, frozen-like, or repository behavior, use Elasticsearch filesystem (`fs`) repositories mounted into the Elasticsearch container. MinIO and S3-compatible services are out of scope for local compose.

Compose output should be marked development-grade in generated report guidance and operator guidance.

Compose can execute locally or on a remote host:

```yaml
deployment:
  target: compose
  scope: remote
  engine: docker
  remote:
    host: bench-host
    user: benchmark
    auth:
      method: ssh_certificate
      ssh_config_host: bench-host
    workdir: /srv/hypothetest/evaluations
```

For MVP remote compose, only SSH certificate-based auth through the user's `.ssh/config` is supported. `deployment.remote.user` may specify the remote SSH username, but do not put identity or certificate file paths in `hypothetest.yml`; the Coordinator validates SSH access and remote permission to execute the selected compose engine before Operator execution.

Remote compose SSH controls the deployment host only. Do not imply that raw dataset files are copied to `deployment.remote.workdir`. Dataset ingestion still happens through the declared loader, such as `espipe` or Rally/esrally, against the Elasticsearch endpoint exposed by the deployment. Only generated compose assets, operator scripts, runtime manifests, and deployment support files belong on the remote SSH host unless the blueprint explicitly declares a remote-generated fixture or remote-local phase script.

## Kubernetes defaults

When target is `kubernetes`, use these defaults unless overridden:

```yaml
deployment:
  target: kubernetes
  namespace: hypothetest
  elasticsearch:
    version: latest
    nodes: 1
    storage: 10Gi
    security: false
    heap: 2g
    memory: 4g
  services:
    kibana: false
  kubernetes:
    operator_version: 3.3.2
    install_operator: true
```

When `kubernetes.provider` is omitted, the Coordinator detects whether a
cluster exists and asks the user before acting. Explicit `provider: k3s`
or `provider: existing` skips the question.

Kubernetes output should be marked development-grade when running on k3s
or similar lightweight distributions. The Coordinator generates CRD
manifests in `generated/eck/` and lifecycle scripts (`eck-up.sh`,
`eck-down.sh`) that follow the same calling convention contract as
compose scripts.

## Dataset loaders

Support both first-class loaders:

```yaml
dataset:
  loader: rally
  track: ./tracks/my-track
  challenge: append-no-conflicts
  params:
    bulk_size: 5000
```

```yaml
dataset:
  loader: espipe
  input: ./data/docs.ndjson
  target: benchmark-index
  options:
    batch_size: 5000
```

Use Rally when the workload is track/challenge oriented. Use espipe when the user wants to load a concrete NDJSON or CSV corpus.

For throughput and merge experiments that do not measure query performance, prefer index-only Rally challenges when available. Full challenges often include query suites that add significant runtime without contributing to the measurement plan.

When `bulk_size` is a parameter or varies across variations, verify warmup safety: compute `total_requests = ceil(dataset_docs / bulk_size)` and check that total requests comfortably exceeds the challenge's warmup period. A `bulk_size` that results in fewer total requests than the warmup window causes Rally to consume the entire dataset during warmup and record no throughput metric.

Rally's CSV report format is the safe default — it is supported by both local installs and the `elastic/rally` container image. JSON report format is not universally available. When the Architect generates measurement extraction code, it should expect CSV input unless the blueprint explicitly declares otherwise.

Dataset locality is defined by the loader, not by the deployment SSH target. For remote compose, local input files, Rally tracks, and espipe inputs remain on the machine running the loader unless the dataset explicitly declares that the Operator must generate the data on the remote host. The SSH host does not receive a copy of raw corpus files as part of normal remote deployment setup.

Dataset fixtures in portable blueprints use one object shape:

- Use `path` for data included in the blueprint or expected to already exist.
- Use `generated_by` for data the Operator should generate during execution.
- Add checksum metadata when the blueprint includes local data.

## Benchmark phases

Represent benchmark work as user-defined phases, not as a fixed enum of operations.

```yaml
evaluation:
  repeats: 3
  order: randomized
  reset:
    - delete_indices
    - clear_caches
    - reload_dataset
    - verify_cluster_green
  phases:
    - name: load_data
      tool: espipe
      with:
        input: ./data/docs.ndjson
        target: benchmark-index
    - name: measured_search
      tool: rally
      with:
        track: ./tracks/search
        challenge: default
```

Allowed initial phase tools:

- `rally`
- `espipe`
- `elasticsearch_api`
- `shell`
- `python`

Use `shell` and `python` only when the hypothesis genuinely needs arbitrary local logic.

Every phase must have a `name` and `tool`. Put tool-specific options under `with`.

## Evaluation script template

Every portable blueprint must include `generated/scripts/evaluation.sh`. Start from `references/evaluation-template.sh`, then replace the generated plan and task functions with the concrete evaluation compiled from `hypothetest.yml`.

The script is the deterministic execution contract. It should:

- Execute prerequisite checks, deployment setup, resets, data loading, workload phases, diagnostics, measurement export, comparison, and report generation in the declared order.
- Use named task functions for each operation, with names derived from variation names, repeat numbers, phase names, and diagnostic collection points.
- Use `run_task <name>` for serial work and `run_parallel <name>...` only for tasks that the hypothesis and measurement plan allow to run concurrently.
- Preserve raw artifacts before summarizing them. Store phase logs, command output, esdiag bundles, measurements, comparisons, and reports under the evaluation directory created by the script.
- Source an optional environment file for local credentials and machine-specific paths, but keep secrets out of blueprint manifests and generated scripts.
- Use environment variables with defaults for paths and run metadata, including `HYPOTHETEST_PLAN`, `HYPOTHETEST_EVALUATION_ROOT`, `HYPOTHETEST_RUN_ID`, `HYPOTHETEST_DRY_RUN`, and `LOG_LEVEL`.
- Keep shell logic explicit. Do not generate a script that infers phase order dynamically from YAML at runtime when the Architect can compile the order ahead of time.
- Make parallel groups deterministic by starting the declared tasks in order and waiting/reporting results in that same order.
- Be written with executable permissions when the output environment supports it; otherwise document `bash generated/scripts/evaluation.sh run` as the execution command.

For multiple repeats, make repeat execution explicit in the generated plan. If the plan randomizes variation order, generate or require a recorded seed and write the resolved order into the evaluation artifacts before execution starts.

### Compilation rules for generated evaluation.sh

These rules apply to every compiled evaluation.sh, regardless of scenario:

- **Delegate dataset loading to `load.sh`.** The compiled evaluation.sh must not inline `esrally`, `espipe`, or other loader calls. All dataset loading calls delegate to `generated/scripts/load.sh`, which the Coordinator generates with the correct environment-specific invocation (container, local binary, remote host). The Architect compiles the phase plan; the Coordinator generates the loader wrapper.
- **Include a `report` subcommand.** The compiled script must support `evaluation.sh report --run-id <ID>` to regenerate comparison and report artifacts from existing measurements without re-running the evaluation. This is critical when the measurement schema or report format changes after a long evaluation completes.
- **Support `--quiet` mode.** When `--quiet` is set, suppress info and debug log output to stdout. Emit only milestones (variation/repeat start and pass/fail), warnings, and errors. Verbose output goes to per-task log files only. This makes backgrounded evaluations monitorable via `tail -f`.
- **Use `run_task` for each variation sub-step.** Each sub-step within a variation (reset, load, collect, measure) should be a separate `run_task` call so each gets its own isolated log file. Do not run the entire variation inline — partial failure diagnosis requires per-step logs.
- **Use `sudo -n` for all privileged commands.** `sudo -n` (non-interactive) fails immediately when no passwordless grant exists, instead of blocking on stdin. Without `-n`, a missing sudoers entry hangs the evaluation silently with no indication of why.
- **Never use `curl -X HEAD` against Elasticsearch.** ES returns a response body on HEAD 404 responses, causing curl to hang waiting for a body that never arrives. Use `curl -s -o /dev/null -w "%{http_code}" -X GET` for existence checks.
- **Include `--max-time` on curl calls.** All `es_api` helper functions and inline curl calls should include `--max-time` with a reasonable default (30s for API calls, 10s for existence checks). The value is scenario-dependent and may be overridden, but the default prevents unresponsive endpoints from hanging the evaluation indefinitely.
- **Redirect background subshells spawned inside `$()`.** When a function backgrounds a subshell (`( while ... ) &`) and the function is called inside a command substitution (`pid=$(start_poller)`), the background process inherits the pipe's write end. If its stdout is not redirected, the `$()` blocks until the background process exits. Redirect to a log file (`>"${logfile}" 2>&1 &`) when the output is valuable, or to `/dev/null` for fire-and-forget processes.
- **Use data-driven comparison and report generation.** `task_compare_results` and `task_write_report` must aggregate all numeric fields present in the measurement YAMLs dynamically, not reference a hardcoded field list. When measurement fields are added or renamed, the comparison and report should pick them up without code changes. Use explicit `is None` checks for missing values — never Python's `or` operator, which treats `0.0` as falsy.

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

For each primary metric, identify at least one plausible source:

- Rally race metrics for latency, throughput, service time, processing time, and operation errors.
- `esdiag` API collections for Elasticsearch indexing, search, merge, segment, store, cache, and node metrics.
- Repository and snapshot APIs for snapshot, restore, searchable snapshot, and filesystem repository behavior.
- espipe output for load duration, bulk errors, and document counts.
- Phase command artifacts for shell or Python outputs.

If a metric source is unclear, keep the metric but mark it as unresolved in `generated/metrics-plan.yml` and call it out before execution.

## Diagnostics

Use `esdiag` as the default Elasticsearch diagnostic collector. Scenario diagnostics are YAML configuration, not JSON. Allow each collection point to declare a specific API list under `measure.diagnostics`.

The `apis` list in `measure.diagnostics.at` declares which API responses the measurement plan requires. The Operator should verify after collection that each listed API has a corresponding file in the unzipped esdiag bundle. Note that esdiag's `--include` flag may use its own named identifiers rather than raw ES API paths — the Operator resolves the mapping. The default esdiag collection already includes `nodes_stats`, `indices_stats`, and `cluster_health`; only list APIs that go beyond the default set if the measurement plan requires them:

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

The Architect should include these API lists in `generated/metrics-plan.yml` and ensure each primary metric maps to Rally, espipe, phase output, an `esdiag` bundle, or diagnostics processed by `esdiag` into a results cluster.

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

## Validation checklist

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
- Deployment target is one of `compose`, `kubernetes`, `existing`, or `elastic-cloud`.
- Dataset loader is `rally` or `espipe`.
- At least two variations exist.
- A baseline is named and exists in variations.
- Each candidate exists in variations.
- Each benchmark phase has a tool.
- Each benchmark phase places tool options under `with`.
- Primary metrics are declared.
- Metric sources are plausible.
- Elasticsearch diagnostic metric sources use `esdiag` collections with explicit API lists.
- When `bulk_size` is a parameter, `total_requests = ceil(dataset_docs / bulk_size)` comfortably exceeds the warmup period for every variation.
- Compose hypotheses include engine handling: `auto`, `docker`, or `podman`.
- Compose hypotheses declare `scope: local` or `scope: remote`.
- Remote compose hypotheses declare SSH certificate auth and require Coordinator readiness validation.
- Snapshot/searchable snapshot hypotheses include filesystem repository configuration for local compose.
- Reports include Markdown and TOON unless the user says otherwise.
- Baseline and candidate names match variation keys exactly.
- Variation setup is explicit and does not depend on previous variations unless `evaluation.reset` says shared state is intentional.
- `generated/scripts/evaluation.sh` exists for portable blueprints and matches the declared evaluation order.
- Any generated parallel task group contains only independent collection or setup work and does not create measurement ambiguity.
- The generated runner preserves raw artifacts before summaries, comparisons, or report generation.
- Interpretation limits identify the workload, dataset, deployment, and Elasticsearch version scope.

When schema-validating generated YAML, use the Rust `yaml-schema` package installed with `cargo install yaml-schema`. The installed CLI is `ys`; validate manifests with this skill's `schemas/blueprint.schema.yaml`. Validate `hypothetest.yml` with the Coordinator-owned `schemas/hypothetest.schema.yaml` when that skill is available. If `cargo` is unavailable, route the user to Coordinator setup before treating schema validation as complete.

## Architect output tone

Return concrete files or patches when possible. Avoid abstract brainstorming once enough information exists. If information is missing, ask for the smallest number of decisions needed to make progress.

## References

- `references/scenario-format.md`
- `references/blueprint.md`
- `references/compose-target.md`
- `references/canonical-schema.md`
- `references/evaluation-template.sh`
- `references/observation-methods.md`
