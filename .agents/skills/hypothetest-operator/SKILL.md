---
name: hypothetest-operator
description: Execute Hypothetest evaluation blueprints. Use when the user has a blueprint with Coordinator-generated assets and wants to run evaluation.sh, collect artifacts, monitor phases, invoke Rally/espipe, or get operator guidance.
---

# Hypothetest Operator Skill

You are the operator for Hypothetest.

Your job is to run the evaluation: execute `evaluation.sh` (which the Architect
compiled), read its logs and output artifacts, and verify the evaluation.yml
index is correct. Think of the Operator as the machinery operator who runs
the plans — no generation, no helper scripts. The Coordinator generates
environment-specific scripts; the Operator calls them through evaluation.sh.
Do not reinterpret the scientific question; if the blueprint is invalid,
return actionable errors and route back to the Architect.

## Initial target priority

Implement `compose` first.

Supported initial deployment targets:

1. `compose`
2. `kubernetes`
3. `existing`
4. `elastic-cloud`

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
- Coordinator readiness evidence (`generated/readiness.toon`) is checked. If absent, the runner warns that tool versions, credentials, dataset access, and deployment prerequisites have not been verified. Execution continues — this is an informed-consent warning, not a hard gate.
- `deployment.target` is supported.
- `dataset.loader` is `rally` or `espipe`.
- `variations` contains at least two entries.
- `experiment.intent`, `experiment.constants`, and `experiment.variables` are declared.
- no factor appears in both `experiment.constants.required` or `experiment.constants.best_effort` and `experiment.variables`.
- `compare.baseline` and every candidate exist in `variations`.
- every evaluation phase has `name` and `tool`.
- every `shell` or `python` phase uses an allowlisted repo-local path.

If validation fails, stop with actionable feedback and point the user back to the Architect. Do not infer or invent missing blueprint or scenario intent.

If Coordinator readiness is absent or stale, the runner warns the user and continues. The warning explains what has not been verified and suggests running the Coordinator to generate readiness evidence.

Output (runner-produced):

```text
evaluations/<hypothesis-name>/<timestamp>/
  evaluation.yml           # schema-valid index of all artifacts
  hypothesis.md            # copy of the experiment hypothesis
  hypothetest.yml          # copy of the plan
  evidence/
    raw/                   # raw API responses, esdiag bundles
    diagnostics/           # before/after diagnostic captures
    phase-output/          # per-variation/repeat espipe output, load manifests
  measurements/            # per-variation/repeat store stats, timing
```

The Analyst produces additional artifacts after consuming the runner
output: normalized measurements, comparisons, charts, summary.toon,
comparison.toon, and report.md. These are not Operator deliverables.

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

For remote compose, treat SSH as the deployment control plane, not the dataset transport. Do not copy raw corpus files to `deployment.remote.workdir` by default. Load data through the declared indexing/workload tool, such as `espipe` or Rally/esrally, against the Elasticsearch endpoint exposed by the remote deployment. Only stage raw data on the remote host when the blueprint explicitly declares remote data generation, a remote download, or a remote-local phase script.

## Compose assets

The Coordinator generates compose infrastructure. The Operator consumes it
via `generated/scripts/compose-up.sh` and `compose-down.sh`. Expected layout:

```text
generated/compose/compose.yml
generated/compose/.env
generated/compose/elasticsearch.yml
generated/compose/repositories/
generated/compose/volumes/
```

The Operator does not generate or modify these assets.

## Kubernetes assets

The Coordinator generates kubernetes infrastructure. The Operator consumes it
via `generated/scripts/eck-up.sh` and `eck-down.sh`. When the provider is k3s,
`generated/scripts/k3s-install.sh` and `k3s-uninstall.sh` handle the cluster
lifecycle independently. Expected layout:

```text
generated/eck/namespace.yaml
generated/eck/elasticsearch.yaml
generated/eck/kibana.yaml          (only when services.kibana: true)
generated/scripts/eck-up.sh
generated/scripts/eck-down.sh
generated/scripts/k3s-install.sh   (only when provider: k3s)
generated/scripts/k3s-uninstall.sh (only when provider: k3s)
```

The Operator does not generate or modify these assets.

## Execution loop

Use this loop unless the scenario explicitly opts out:

```text
for repeat in repeats:
  for variation in randomized_or_declared_order:
    record_variation_started_at
    provision_or_reset_deployment
    wait_for_cluster_ready
    load_dataset
    apply_variation_setup
    execute_evaluation_phases
    collect_metrics
    archive_artifacts
    record_variation_completed_at_and_runtime
```

A variation must not inherit experimental state from another variation unless the scenario explicitly says so.

`load_dataset` means invoking the declared loader from its configured execution location. For remote compose, this usually means the Operator runs the loader from the coordinator/operator machine using loader-local input files and sends documents to the remote Elasticsearch endpoint. It does not mean copying the raw dataset to the SSH host.

Honor `experiment.constants` when provisioning and executing variations. Required constants must remain unchanged across variations; if execution discovers that a required constant cannot be held, stop and preserve partial artifacts. Best-effort constants should be applied when the target supports them; when the target manages or approximates them, record the resolved behavior in the evaluation manifest and report inputs.

Default reset behavior is:

```yaml
evaluation:
  reset:
    - delete_indices
    - clear_caches
    - reload_dataset
    - verify_cluster_green
```

For force-merge, snapshot, restore, searchable snapshot, and frozen-like workflows, collect pre/post stats around every setup step that changes index layout, repository state, or cache state.

## Dataset loading

Support initial loaders:

Blueprint datasets may declare `path` for included or pre-existing data, or
`generated_by` for data the Operator must generate during execution. Record
generator command, parameters, output target, and observed size/document count
in the evaluation manifest.

Dataset paths are loader-local unless the dataset or phase explicitly says
otherwise. For remote compose, keep included datasets, Rally tracks, and espipe
inputs on the machine that runs the loader. The remote SSH host only needs the
compose deployment assets and runtime support files unless a remote-local data
source is explicitly declared.

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

Before any phase that can destroy or reset the only recoverable copy of state, run a diagnostics preflight for every configured collection path. For `esdiag`, verify the same runtime environment that will execute collection has the required endpoint credentials, source files, keystore access, and `ESDIAG_KEYSTORE_PASSWORD` when an encrypted keystore is used. If diagnostics provide primary metrics or required evidence, a failed preflight is a hard stop before destructive reset or teardown.

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

## During-phase observation

When `measure.diagnostics.during` is declared and its profile is not `none`,
the Coordinator generates `generated/scripts/sample.sh` — a sampling script
that collects interval-based observations while phases execute. The Operator
does not generate this script; it runs it.

### Invocation

When during-phase observation is active, evaluation.sh task functions for
workload phases delegate to sample.sh instead of running the phase command
directly:

```bash
./generated/scripts/sample.sh "$VARIATION" "$REPEAT" "$PHASE_NAME" \
  espipe load --input ./data/docs.ndjson --target benchmark-index
```

When `diagnostics.during` is absent or `profile: none`, evaluation.sh calls
the phase command directly — no sample.sh wrapper.

When `diagnostics.during.phases` lists specific phase names, only those
phases are wrapped. When omitted, all evaluation phases are wrapped.

### Structured stdout

sample.sh writes structured `[tag] key=value` lines to stdout.
evaluation.sh's `run_task` captures these to `${HYPOTHETEST_LOG_DIR}/<task>.log`.
The Operator reads the log files to determine phase outcomes.

| Tag | Meaning |
|---|---|
| `[start]` | Phase sampling began; includes variation, repeat, phase, interval, methods |
| `[sample]` | One sample collected; includes t, method, key signal values |
| `[skip]` | Sample skipped; reason is `collection_slow` or `short_phase` |
| `[error]` | Collection failed for one method at time t; sampling continues |
| `[phase_complete]` | Phase finished; includes elapsed time and exit code |

When sample.sh backgrounds the phase command, both the phase's stdout and
sampling `[tag]` lines land in the same log file. Parse by `[tag]` prefix,
not by line position.

### Exit codes

| Code | Meaning | Operator action |
|---|---|---|
| 0 | Phase succeeded, sampling complete | Continue to next phase |
| Non-zero | Phase command exited non-zero | Record failure, apply `continue_on_error` policy |

sample.sh passes through the phase command's exit code. Sampling failures
(API unreachable, slow collection) are logged but do not change the exit code.

### Output layout

All artifacts land under `${HYPOTHETEST_EVIDENCE_DIR}/during/`:

```
${HYPOTHETEST_EVIDENCE_DIR}/during/
  <variation>-<repeat>-<phase>-<method>.toon   # time-series (use, latency)
  <variation>-<repeat>-<phase>-tsa/            # text archive (TSA)
  <variation>-<repeat>-<phase>-on_cpu/         # perf archive
  <variation>-<repeat>-<phase>-off_cpu/        # bpftrace archive
  <variation>-<repeat>-<phase>-raw/            # raw API responses (debugging)
```

Methods that produce time-series (use, latency) write TOON files. Methods
that produce snapshots (tsa, on_cpu, off_cpu) write directories. Raw API
responses are always archived regardless of method.

## Evaluation Record

The runner generates `evaluation.yml` as the schema-valid index of the
completed or partial evaluation. It must validate against this skill's
bundled `schemas/evaluation.schema.yaml` and point to the preserved
evidence and raw measurements.

The runner records:

- `name`, `hypothesis`, `plan` — identity and source references
- `manifest` — runtime metadata: start/end times, status, blueprint,
  plan, variations list, repeats, quality label, and per-variation
  runtime
- `evidence` — paths to raw API responses, diagnostics, phase output
- `measurements` — primary and secondary metric names; `normalized`
  is left empty for the Analyst to populate
- `comparisons` — baseline, candidates; `artifacts` and `decision`
  are left empty for the Analyst to populate

Record runtime explicitly. `manifest.runtime.total_seconds` is the
elapsed wall-clock time from evaluation start to completion or failure.
`manifest.runtime.variations` records each variation's elapsed
wall-clock runtime. Compute variation runtime from the start of that
variation's reset/provisioning through artifact archival, so loading,
phases, diagnostics, and archive cost are included.

The Operator does not produce `manifest.toon`, `summary.toon`,
`comparison.toon`, normalized measurements, charts, or `report.md`.
Those are Analyst deliverables produced after consuming the runner
output.

## Failure behavior

The generated runner writes a partial `evaluation.yml` on failure via an
ERR trap. The partial index records:

- `manifest.status: failed` and `manifest.quality: incomplete`
- `manifest.failures` with the failed task name and exit code
- Whatever evidence artifacts (raw measurements, diagnostics, phase output)
  existed at the time of failure

If diagnostics collection fails, preserve deployment state and raw evidence before teardown whenever that state is needed to recover primary metrics or explain the failure. Do not delete volumes or otherwise destroy the only remaining source of required metrics after a diagnostics credential or access failure unless the scenario explicitly says cleanup is more important than recoverability.

Partial evaluations are valid Analyst inputs as long as `evaluation.yml` records what completed, what failed, and where raw artifacts live.

## Safety and reproducibility

- Do not delete arbitrary host paths.
- Only delete paths generated by Hypothetest or explicitly specified by the scenario.
- Do not run destructive teardown that would erase unrecovered primary metrics or required diagnostic evidence after a tool credential/access failure.
- Redact API keys and passwords from logs.
- Write the exact commands used.
- Prefer idempotent scripts.

## References

- `references/artifacts.md`
