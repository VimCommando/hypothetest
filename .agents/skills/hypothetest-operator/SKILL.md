---
name: hypothetest-operator
description: Implement and run Hypothetest Elasticsearch benchmark plans. Use when the user has hypothetest.yml and wants compose/Docker/Podman assets, execution scripts, run artifacts, monitoring, Rally/espipe invocation, or operator runbooks.
---

# Hypothetest Operator Skill

You are the operator for Hypothetest.

Your job is to turn `hypothetest.yml` into executable assets, run or prepare benchmark execution, monitor phases, and preserve artifacts. Do not reinterpret the scientific question; if the plan is invalid, return actionable errors and route back to the architect.

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
hypothetest.yml
```

Before generating or running anything, validate that:

- `apiVersion` is `hypothetest.elastic/v1`.
- `kind` is `BenchmarkScenario`.
- `spec.deployment.target` is supported.
- `spec.dataset.loader` is `rally` or `espipe`.
- `spec.variations` contains at least two entries.
- `spec.comparison.baseline` and every candidate exist in `spec.variations`.
- every benchmark phase has `name`, `runner`, and `config`.
- every `shell` or `python` phase uses an allowlisted repo-local path.

If validation fails, stop with actionable feedback and point the user back to the Architect. Do not infer or invent missing scenario intent.

Output:

```text
runs/<scenario>/<timestamp>/
  manifest.toon
  scenario.md
  hypothetest.yml
  generated/
  variations/
    <variation>/
      repeat-<n>/
        phase-logs/
        metrics/
        raw/
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

For `scope: remote`, require Coordinator readiness evidence before execution. The remote host must be reachable through the user's `.ssh/config` using SSH certificate auth, and the remote user must be able to run the resolved compose command:

- `docker compose version` for Docker.
- `podman compose version` or `podman-compose --version` for Podman.

Run compose operations on the remote host in the declared `deployment.remote.workdir`. Do not attempt remote execution when SSH access or compose permissions are unverified.

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
    run_benchmark_phases
    collect_metrics
    archive_artifacts
```

A variation must not inherit experimental state from another variation unless the scenario explicitly says so.

Default isolation is:

```yaml
isolation:
  mode: reset_between_variations
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

Dataset bundle modes:

- `static`: load the bundle-local dataset file and verify its checksum when provided.
- `dynamic`: execute the declared generator during the run, such as Rally producing a large nginx log corpus. Record generator command, parameters, seed, output target, and observed size/document count in the run manifest.

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

## Benchmark runners

Initial runners:

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

Never run arbitrary inline shell or Python from the scenario. A phase must reference a file that is either repo-local or matched by an allowlist in the canonical plan.

## Metrics collection

Collect raw metrics before summarizing. Use `esdiag` as the default Elasticsearch diagnostic collector.

For each configured collection point, run `esdiag collect` with the scenario's YAML-defined API list or source definition. Use `--sources <path/to/sources.yml>` when the collection endpoints must follow a generated source file. Preserve the raw `esdiag` diagnostic bundle as its `.zip` artifact; do not convert raw API outputs to TOON.

Default Elasticsearch API collection around each phase:

- `_cluster/health`
- `_nodes/stats`
- `_stats`
- `_cat/segments?format=json`
- `_cat/indices?format=json`

For force-merge phases, collect segment and store stats before and after.

For snapshot/frozen-like phases, collect repository/snapshot information when available.

If a scenario provides `spec.diagnostics.collections`, honor those API lists exactly for that collection point. Do not add broader diagnostics unless the plan explicitly requests them.

If the scenario configures a diagnostics results target, run `esdiag process` to ship the bundle to that results cluster and record the destination in the run manifest.

Store Hypothetest's own derived metric rows as TOON (`.toon`), not JSON or CSV. Normalize metric records where possible to TOON rows shaped like:

```toon
metrics[2]{scenario,run_id,deployment_target,variation,repeat,phase,metric,value,unit,source,status}:
  example,run-001,compose,baseline,1,warm_search,search_latency_p99,120,ms,rally,ok
  example,run-001,compose,candidate,1,warm_search,search_latency_p99,150,ms,rally,ok
```

## Run manifest

Create `manifest.toon` with:

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

- `run_id`
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

Partial runs are valid Analyst inputs as long as `manifest.toon` records what completed, what failed, and where raw artifacts live.

## Safety and reproducibility

- Do not delete arbitrary host paths.
- Only delete paths generated by Hypothetest or explicitly specified by the scenario.
- Redact API keys and passwords from logs.
- Write the exact commands used.
- Prefer idempotent scripts.

## References

- `references/operator-runbook.md`
- `references/artifacts.md`
