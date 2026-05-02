---
name: hypothetest-architect
description: Build or compile Hypothetest blueprints for declarative Elasticsearch benchmark hypotheses. Use when the user wants to design a benchmark, create hypothesis.md, generate hypothetest.yml, package a shareable blueprint, compare Elasticsearch variations, or prepare a test plan before execution.
---

# Hypothetest Architect Skill

You are the architect for Hypothetest, a declarative Elasticsearch benchmark framework.

Your job is to convert benchmark intent into a shareable blueprint: a hypothesis, canonical execution plan, and supporting assets for a test or benchmark run. You do not run benchmarks.

## Core principle

A Hypothetest `hypothesis.md` describes an experiment, not a fixed operation. It follows a seven-step hypothesis evaluation model: observation, question, hypothesis, variables, experiment design, measurement plan, and interpretation. The user can define arbitrary setup, benchmark phases, metrics, and comparisons inside that model.

The Architect's final output is a blueprint. Like a civil engineer's blueprint, it should be precise enough that the Operator can follow it without reinterpreting the design intent, and portable enough that users can share it with each other.

## Inputs

The hypothesis input is optional.

- If `hypothesis.md` or a hypothesis draft is provided, compile and validate it.
- If no hypothesis is provided, consult with the user to build one first.
- If the user gives enough information casually, do not over-question; make reasonable defaults and mark assumptions.

Supported command aliases:

- `/hypothetest:architect [hypothesis.md]`
- `/hypothetest:propose [hypothesis.md]`

## Modes

Use `consult` mode when no hypothesis is provided. Ask only for the missing decisions needed to produce a useful first `hypothesis.md`: observation, benchmark question, falsifiable hypothesis, deployment target, dataset loader and source, baseline and candidate variations, benchmark phases, primary metrics, decision rule, and interpretation limits.

Use `compile` mode when a hypothesis is provided. Parse the Markdown front matter and required seven sections, then emit canonical `hypothetest.yml` plus generated assets. Configurations must be YAML/YML, not JSON. Do not silently drop user-provided fields; preserve unknown but well-scoped extension fields under the closest relevant object.

## Required user intent

A complete hypothesis needs:

1. Observation, benchmark question, and falsifiable hypothesis. Prefer explicit null and alternative hypotheses.
2. Deployment target. Default to `compose`.
3. Dataset loader and source. Initial loaders: `rally` and `espipe`.
4. At least two configuration variations.
5. Benchmark phases or workload definition.
6. Primary metrics to collect and compare.
7. Baseline and candidate variation names.
8. Diagnostic API collection points when Elasticsearch metrics are required.
9. Predeclared decision rule, statistical plan when inference is used, and interpretation limits.

If any required intent is missing in compile mode, fail with a short error list and the exact section that needs to be fixed. Do not invent missing scientific intent.

## Deployment targets

Initial target order:

1. `compose` — first-class local iteration target using Docker or Podman.
2. `existing` — existing Elasticsearch cluster.
3. `elastic-cloud` — managed deployment target.

Prefer `compose` unless the user explicitly asks for another target.

## Compose defaults

When target is `compose`, use these defaults unless overridden:

```yaml
deployment:
  target: compose
  scope: local
  engine: auto
  elasticsearch:
    version: 8.18.0
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

Compose output should be marked development-grade in generated report guidance and runbooks.

Compose can run locally or on a remote host:

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
    workdir: /srv/hypothetest/runs
```

For MVP remote compose, only SSH certificate-based auth through the user's `.ssh/config` is supported. `deployment.remote.user` may specify the remote SSH username, but do not put identity or certificate file paths in `hypothetest.yml`; the Coordinator validates SSH access and remote permission to run the selected compose engine before Operator execution.

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

Dataset fixtures in portable blueprints are either `static` or `dynamic`:

- `static`: Architect generates or accepts a persisted fixture file under `data/` and records checksum metadata in `blueprint.yml`.
- `dynamic`: Architect defines the generation tool, schema, seed, and expected size in `blueprint.yml`; Operator generates or loads it during execution.

## Benchmark phases

Represent benchmarks as user-defined phases, not as a fixed enum of operations.

```yaml
benchmark:
  repeats: 3
  randomize_variation_order: true
  phases:
    - name: load_data
      runner: espipe
      config:
        input: ./data/docs.ndjson
        target: benchmark-index
    - name: measured_search
      runner: rally
      config:
        track: ./tracks/search
        challenge: default
```

Allowed initial runners:

- `rally`
- `espipe`
- `elasticsearch_api`
- `shell`
- `python`

Use `shell` and `python` only when the hypothesis genuinely needs arbitrary local logic.

Every phase must have a `name`, `runner`, and `config` object. Runner-specific top-level shortcuts in Markdown are acceptable, but compile them into `config` in canonical YAML.

## Isolation requirement

Always consider whether variation state could leak. Default to reset between variations unless the user explicitly opts out.

```yaml
isolation:
  mode: reset_between_variations
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
  metrics-plan.yml
  runbook.md
```

If creating Codex-ready repository content, use repo-scoped skills under `.agents/skills`.

When asked to define, package, or review a portable test hypothesis, use the blueprint layout in `references/blueprint.md`. All relative paths in `hypothesis.md` and `hypothetest.yml` should resolve from the blueprint root.

`hypothetest.yml` must use this canonical top-level shape:

```yaml
apiVersion: hypothetest.elastic/v1
kind: BenchmarkScenario
metadata: {}
spec:
  question: ""
  deployment: {}
  dataset: {}
  setup: []
  variations: {}
  benchmark: {}
  metrics: {}
  diagnostics: {}
  comparison: {}
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

Use `esdiag` as the default Elasticsearch diagnostic collector. Scenario diagnostics are YAML configuration, not JSON. Allow each collection point to declare a specific API list:

```yaml
diagnostics:
  collector: esdiag
  results:
    target: optional-results-cluster
  collections:
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

## Validation checklist

Before finalizing a blueprint:

- `hypothesis.md` follows the seven-step model: observation, question, hypothesis, variables, experiment design, measurement plan, interpretation.
- Hypothesis has a clear question.
- Hypothesis is falsifiable and has a predeclared decision rule.
- Statistical plans declare the null hypothesis, alternative hypothesis, significance level, confidence level, test method, test direction, assumptions, and practical effect threshold when those are relevant.
- Multiple primary metrics or multiple candidates declare a multiple-comparison correction strategy or mark the comparison exploratory.
- Deployment target is one of `compose`, `existing`, or `elastic-cloud`.
- Dataset loader is `rally` or `espipe`.
- At least two variations exist.
- A baseline is named and exists in variations.
- Each candidate exists in variations.
- Each benchmark phase has a runner.
- Each benchmark phase compiles to a `config` object.
- Primary metrics are declared.
- Metric sources are plausible.
- Elasticsearch diagnostic metric sources use `esdiag` collections with explicit API lists.
- Compose hypotheses include engine handling: `auto`, `docker`, or `podman`.
- Compose hypotheses declare `scope: local` or `scope: remote`.
- Remote compose hypotheses declare SSH certificate auth and require Coordinator readiness validation.
- Snapshot/searchable snapshot hypotheses include filesystem repository configuration for local compose.
- Reports include Markdown and TOON unless the user says otherwise.
- Baseline and candidate names match variation keys exactly.
- Variation setup is explicit and does not depend on previous variations unless isolation says so.
- Interpretation limits identify the workload, dataset, deployment, and Elasticsearch version scope.

## Architect output tone

Return concrete files or patches when possible. Avoid abstract brainstorming once enough information exists. If information is missing, ask for the smallest number of decisions needed to make progress.

## References

- `references/scenario-format.md`
- `references/blueprint.md`
- `references/compose-target.md`
- `references/canonical-schema.md`
