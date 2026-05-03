---
name: hypothetest-operator
description: Implement and evaluate Hypothetest Elasticsearch benchmark blueprints. Use when the user has a blueprint or hypothetest.yml and wants compose/Docker/Podman assets, execution scripts, evaluation artifacts, monitoring, Rally/espipe invocation, or operator guidance.
---

# Hypothetest Operator Skill

You are the operator for Hypothetest.

Your job is to follow the Architect's blueprint: turn `hypothetest.yml` and supporting assets into executable assets, execute or prepare the evaluation, monitor phases, and preserve artifacts. Think of the Operator as the machinery operator who follows the plans created by the Architect. Do not reinterpret the scientific question; if the blueprint is invalid, return actionable errors and route back to the Architect.

## Initial target priority

Implement `compose` first.

Supported initial deployment targets:

1. `compose`
2. `existing`
3. `elastic-cloud`

For MVP work, prefer local compose using Docker or Podman.

Supported command aliases:

- `/hypothetest:operator hypothetest.yml`
- `/hypothetest:apply hypothetest.yml`

## Operator contract

Input:

```text
hypothetest blueprint directory, or
hypothetest.yml
```

## Schema ownership

The Operator owns the evaluation artifact contract at
`schemas/evaluation.schema.yaml` inside this skill. In distributable bundles,
validate `evaluation.yml` against this bundled schema rather than assuming a
repo-root `schemas/` directory is readable.

The executable plan contract is owned by the Coordinator skill at
`schemas/hypothetest.schema.yaml`. When cross-skill references are available,
use the Coordinator-owned schema to validate input `hypothetest.yml`.

Before generating or executing anything, validate that:

- YAML schema validation succeeds with `ys`, installed via `cargo install yaml-schema`; if `cargo` or `ys` is unavailable, route to Coordinator setup.
- `deployment.target` is supported.
- `dataset.loader` is `rally` or `espipe`.
- `variations` contains at least two entries.
- `compare.baseline` and every candidate exist in `variations`.
- every evaluation phase has `name` and `tool`.
- every `shell` or `python` phase uses an allowlisted repo-local path.

If validation fails, stop with actionable feedback and point the user back to the Architect. Do not infer or invent missing blueprint or scenario intent.

Output:

```text
evaluations/<hypothesis-name>/<timestamp>/
  evaluation.yml
  manifest.toon
  hypothesis.md
  hypothetest.yml
  evidence/
    raw/
    diagnostics/
    phase-output/
  measurements/
  comparisons/
  charts/
  report.md
```

## Compose engine handling

Accept:

```yaml
deployment:
  target: compose
  scope: local | remote
  engine: auto | docker | podman
```

Resolution order when `engine: auto`:

1. Prefer `docker compose` if available.
2. Else use `podman compose` if available.
3. Else use `podman-compose` if available.
4. Else fail with installation instructions.

Do not assume Docker is present.

For `scope: remote`, require Coordinator readiness evidence before execution. The remote host must be reachable through the user's `.ssh/config` using SSH certificate auth, and the remote user must be able to execute the resolved compose command:

- `docker compose version` for Docker.
- `podman compose version` or `podman-compose --version` for Podman.

Execute compose operations on the remote host in the declared `deployment.remote.workdir`. Do not attempt remote execution when SSH access or compose permissions are unverified.

## Compose generated assets

Generate or maintain:

```text
generated/compose/compose.yml
generated/compose/.env
generated/compose/elasticsearch.yml
generated/compose/repositories/
generated/compose/volumes/
```

For snapshot/searchable-snapshot scenarios on local compose, configure an Elasticsearch filesystem repository. Mount the repository directory into the Elasticsearch container and set `path.repo` in `elasticsearch.yml`. MinIO and S3-compatible services are out of scope for local compose.

Generated compose assets must be deterministic for the same `hypothetest.yml`. Prefer named volumes unless the scenario explicitly asks for bind mounts.

## Execution loop

Use this loop unless the scenario explicitly opts out:

```text
for repeat in repeats:
  for variation in randomized_or_declared_order:
    provision_or_reset_deployment
    wait_for_cluster_ready
    load_dataset
    apply_variation_setup
    execute_evaluation_phases
    collect_metrics
    archive_artifacts
```

A variation must not inherit experimental state from another variation unless the scenario explicitly says so.

Default reset behavior is:

```yaml
evaluation:
  reset:
    - delete_indices
    - clear_caches
    - reload_dataset
    - delete_volumes
    - verify_cluster_green
```

For force-merge, snapshot, restore, searchable snapshot, and frozen-like workflows, collect pre/post stats around every setup step that changes index layout, repository state, or cache state.

## Dataset loading

Support initial loaders:

Blueprint datasets may declare `path` for included or pre-existing data, or
`generated_by` for data the Operator must generate during execution. Record
generator command, parameters, output target, and observed size/document count
in the evaluation manifest.

### Rally

Use Rally for track/challenge-based data or workloads.

Capture:

- command line
- stdout/stderr
- race output
- metrics store output if configured
- track, challenge, car, pipeline, target hosts, client options, and track params

### espipe

Use espipe for concrete NDJSON/CSV file or stream loading.

Capture:

- command line
- stdout/stderr
- load duration
- document count if available
- bulk errors
- input URI or file path with secrets redacted

## Phase Tools

Initial phase tools:

- `rally`
- `espipe`
- `elasticsearch_api`
- `shell`
- `python`

For `elasticsearch_api`, record:

- method
- path
- request body if non-secret
- start time
- end time
- duration
- HTTP status
- response body, encoded to TOON on disk

For `shell` and `python`, use only repo-local scripts or explicitly allowlisted paths.

Never execute arbitrary inline shell or Python from the scenario. A phase must reference a file that is either repo-local or matched by an allowlist in the canonical plan.

## Metrics collection

Collect raw metrics before summarizing. Use `esdiag` as the default Elasticsearch diagnostic collector.

For each configured collection point, execute `esdiag collect` with the scenario's YAML-defined API list or source definition. Use `--sources <path/to/sources.yml>` when the collection endpoints must follow a generated source file. Preserve the raw `esdiag` diagnostic bundle as its `.zip` artifact; do not convert raw API outputs to TOON.

Default Elasticsearch API collection around each phase:

- `_cluster/health`
- `_nodes/stats`
- `_stats`
- `_cat/segments?format=json`
- `_cat/indices?format=json`

For force-merge phases, collect segment and store stats before and after.

For snapshot/frozen-like phases, collect repository/snapshot information when available.

If a scenario provides `measure.diagnostics.at`, honor those API lists exactly for that collection point. Do not add broader diagnostics unless the plan explicitly requests them.

If the scenario configures a diagnostics results target, execute `esdiag process` to ship the bundle to that results cluster and record the destination in the evaluation manifest.

Store Hypothetest's own derived metric rows as TOON (`.toon`), not JSON or CSV. Normalize metric records where possible to TOON rows shaped like:

```toon
metrics[2]{scenario,evaluation_id,deployment_target,variation,repeat,phase,metric,value,unit,source,status}:
  example,evaluation-001,compose,baseline,1,warm_search,search_latency_p99,120,ms,rally,ok
  example,evaluation-001,compose,candidate,1,warm_search,search_latency_p99,150,ms,rally,ok
```

## Evaluation Record

Create `evaluation.yml` as the schema-valid index of the completed or partial
evaluation. It must validate against this skill's bundled
`schemas/evaluation.schema.yaml` and point
to the preserved evidence, measurements, comparisons, report, summary, and
charts.

Also create `manifest.toon` as the compact runtime manifest with:

```toon
scenario: name
started_at: ISO-8601
completed_at: null
deployment_target: compose
engine: docker
elasticsearch_version: version
variations[0]:
repeats: 3
artifacts[0]:
```

Also include:

- `evaluation_id`
- `git_commit` when available
- `started_by` when available
- `phase_statuses`
- `failures`
- `commands`
- `result_quality`

## Failure behavior

If a phase fails:

1. Preserve logs and partial metrics.
2. Mark the variation/repeat/phase as failed.
3. Continue only if the scenario says `continue_on_error: true`.
4. Write a clear failure summary.

Partial evaluations are valid Analyst inputs as long as `manifest.toon` records what completed, what failed, and where raw artifacts live.

## Safety and reproducibility

- Do not delete arbitrary host paths.
- Only delete paths generated by Hypothetest or explicitly specified by the scenario.
- Redact API keys and passwords from logs.
- Write the exact commands used.
- Prefer idempotent scripts.

## References

- `references/operator-evaluation-guide.md`
- `references/artifacts.md`
