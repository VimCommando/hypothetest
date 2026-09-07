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

Prefer `compose` for local iteration.

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
`schemas/hypothetest.schema.yaml`. Use the Coordinator-owned schema to validate input `hypothetest.yml`.

## Workflow

1. Read the shared [execution contract](../hypothetest-coordinator/references/execution-contract.md). Validate the plan with `ys` and the Coordinator schema. Missing schema/tooling routes to Coordinator; invalid scientific intent routes to Architect.
2. Apply the shared readiness decision table. Verify generated helpers and deployment assets using [deployment assets](references/deployment-assets.md). Required checks must pass in the execution context; pending provisioned-target checks must gate reset/load.
3. Run the Architect-compiled evaluation.sh from the blueprint root. Verify [run lessons](references/run-lessons.md) exist before destructive setup. Follow compiled order and declared concurrency.
4. Monitor task logs and archive [workload evidence](references/workload-evidence.md). For during-phase sampling, use [observation logs and outcomes](references/during-observation.md). Preserve raw output before deriving metrics.
5. On failure, retain partial artifacts and state needed for required evidence. Return invalid generation or environment bindings to the responsible role rather than inventing helper scripts.
6. Verify complete or partial evaluation.yml against the bundled schema and check each indexed path exists. Confirm variation/repeat coverage, runtimes, failure status, and evidence gaps. Hand the directory to Analyst using the shared artifact-ownership table.

Before execution, check baseline/candidate names, at least 2 variations, phase tools/options, declared experiment intent and constants/variables, and repo-local or allowlisted script paths. No factor may be both a constant and a variable.

Output (runner-produced):

```text
evaluations/<hypothesis-name>/<timestamp>/
  evaluation.yml           # schema-valid index of all artifacts
  hypothesis.md            # copy of the experiment hypothesis
  hypothetest.yml          # copy of the plan
  lessons.md               # run-local operator/user feedback for future improvements
  evidence/
    raw/                   # raw API responses, esdiag bundles
    diagnostics/           # before/after diagnostic captures
    phase-output/          # per-variation/repeat espipe output, load manifests
  measurements/            # per-variation/repeat store stats, timing
```

The Analyst produces additional artifacts after consuming the runner
output: normalized measurements, comparisons, charts, summary.toon,
comparison.toon, and report.md. These are not Operator deliverables.

## Execution loop

Use this loop unless the scenario explicitly opts out:

```text
for repeat in repeats:
  for variation in randomized_or_declared_order:
    record_variation_started_at
    provision_or_reset_deployment
    wait_for_cluster_ready
    apply_pre_load_variation_setup
    gate_before_load_if_required
    load_dataset
    apply_declared_post_load_setup
    execute_evaluation_phases_with_declared_gates
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

## Metrics collection

Collect raw metrics before summarizing. Use `esdiag` as the default Elasticsearch diagnostic collector.

Before any phase that can destroy or reset the only recoverable copy of state, run a diagnostics preflight for every configured collection path. For `esdiag`, verify the same runtime environment that will execute collection has the required endpoint credentials, source files, keystore access, and `ESDIAG_KEYSTORE_PASSWORD` when an encrypted keystore is used. If diagnostics provide primary metrics or required evidence, a failed preflight is a hard stop before destructive reset or teardown.

Execute the Coordinator-resolved diagnostics command for each collection point. Use the [diagnostics-selection contract](../hypothetest-coordinator/references/execution-contract.md#diagnostics-selection); required unresolved selections block execution. Preserve raw esdiag bundles and API response formats.

Default Elasticsearch API collection around each phase:

- `_cluster/health`
- `_nodes/stats`
- `_stats`
- `_cat/segments?format=json`
- `_cat/indices?format=json`

For force-merge phases, collect segment and store stats before and after.

For snapshot/frozen-like phases, collect repository/snapshot information when available.

Verify the resolved command covers the declared selection. A standard bundle is allowed only when consistent with that selection.

If the scenario configures a diagnostics results target, execute `esdiag process` to ship the bundle to that results cluster and record the destination in the evaluation manifest.

Write wide run measurements according to the shared [metric normalization contract](../hypothetest-analyst/references/metric-normalization.md). Preserve distinct phase/operation dimensions in metric column identities.

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
- `evidence.generated` includes lessons.md as a generated Markdown artifact, including partial evaluations

Record runtime explicitly. `manifest.runtime.total_seconds` is the
elapsed wall-clock time from evaluation start to completion or failure.
`manifest.runtime.variations` records each variation's elapsed
wall-clock runtime. Compute variation runtime from the start of that
variation's reset/provisioning through artifact archival, so loading,
phases, diagnostics, and archive cost are included.

Use the shared artifact-ownership table for Analyst deliverables. The initial handoff requires evaluation.yml, not manifest.toon.

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
