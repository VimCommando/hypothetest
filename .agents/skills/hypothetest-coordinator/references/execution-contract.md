# Execution contract

Read this contract when compiling a runner, binding an environment, or executing a blueprint. Bundle it with portable skill distributions. If it is unavailable, recover the reference before declaring the handoff ready.

## Artifact ownership

| Producer | Deliverables | Next consumer |
|---|---|---|
| Architect | Hypothesis, blueprint, canonical plan, deterministic evaluation.sh, metrics plan | Coordinator |
| Coordinator | Readiness evidence, environment scripts, deployment assets, resolved diagnostics commands | Operator |
| Operator runner | evaluation.yml, copied inputs, raw evidence, wide run measurements, logs, run-local lessons | Analyst |
| Analyst | manifest.toon derived from evaluation.yml, normalized measurements, comparison.toon, summary.toon, report, charts, optional dashboards | User |

The Operator owns the [evaluation index schema](../../hypothetest-operator/schemas/evaluation.schema.yaml). The Analyst adds references to its outputs in that index without changing recorded execution facts. An existing manifest.toon is optional input; reconcile it against evaluation.yml and disclose discrepancies.

Use the Analyst's [metric normalization contract](../../hypothetest-analyst/references/metric-normalization.md) for wide run tables and comparison calculations. Preserve source artifacts in their original format before producing derived TOON. Index raw measurement files under evidence with kind `measurement`; leave measurements.normalized and comparisons.artifacts empty until analysis.

## Readiness decisions

Apply the most restrictive applicable row before workload execution or destructive reset.

| Evidence | Decision |
|---|---|
| Required access or a required constant failed; status is blocked | Stop. Preserve evidence and return the failed check to Coordinator or Architect. |
| Readiness absent or stale | Return to Coordinator to run the required preflights and regenerate affected bindings. File absence alone is not proof of failure, but execution requires current evidence. |
| Only target checks await runner provisioning; pre-provisioning checks passed | Hand off as ready_with_warnings for provisioning only. List pending_provisioning checks and require their runtime gates before reset/load. |
| Optional tools unavailable, all required checks passed | Continue as ready_with_warnings. Name unavailable metrics and interpretation limits. |
| All required checks passed in the actual execution context | Continue as ready. |

Readiness becomes stale when the plan, generated commands, endpoint, target, authentication source, dataset, or execution context changes. Record these identities and check timestamps without secret values. Revalidate affected checks; installation alone proves no endpoint access.

For a cluster provisioned by the runner, record target API checks as pending until provisioning. Generate an early access gate after provisioning and before reset/load. This is a preparation handoff, not permission to skip runtime verification. The gate must pass before measurements or destructive work begin.

The Coordinator classifies each observation method as required evidence or optional diagnostics from the metric plan. A missing package is a warning only if required metrics remain collectable. If no observation package is usable, mark an explicitly optional during block unavailable; otherwise block it.

## Remote Compose

SSH controls deployment through the declared SSH config host and certificate auth. Docker or Podman's directly published service port is the benchmark data plane. Verify the actual loader and diagnostics clients can reach it from their execution context.

Loaders and diagnostic clients run on the local Operator host unless the blueprint explicitly declares another locality. DNS, routing, firewall, or tool connectivity failures block readiness. Resolve those failures directly; do not generate SSH tunnels, loopback forwards, or proxy workarounds. Stage deployment assets and runtime support over SSH, with raw data staged only for an explicitly declared remote-local phase or fixture.

## Force-merge isolation

For force-merge experiments, compile serial gates before load, after load before the measured force merge, and after force merge before another variation or repeat. Each gate requires all of the following across consecutive polls:

1. Zero active node merges.
2. Zero active and queued merge-thread-pool work.
3. Zero force-merge tasks.

Declare poll interval, timeout, and required consecutive successes in the generated plan, with at least 2 successes. Preserve timestamps, endpoint, raw responses, counts, and the gate outcome. Missing signals do not count as zero. Timeout or collection failure stops the evaluation and preserves partial artifacts.

## Diagnostics selection

The Architect declares each collection point's requested APIs and required metrics. The Coordinator resolves that intent against the installed collector's help and configuration, then records the concrete command, saved host, output directory, selected APIs, and evidence coverage in the generated metrics plan/readiness artifacts.

Use standard esdiag collection when it covers the requested default bundle. For an exact API list, verify the mapping from Elasticsearch paths to supported collector selectors before generating the command. If the collector cannot express the selection, mark it unresolved and return to Architect for an explicit collector or plan change. A broader default bundle is not an exact selection.

The Operator runs the resolved command and preserves its original output. Required diagnostics preflights must pass in the collection process's environment before reset or teardown can destroy recoverable evidence. After failure, retain state needed to recover primary metrics unless the scenario explicitly prioritizes cleanup.

## Generated script calling convention

The Architect compiles order; the Coordinator fills environment bindings; the Operator executes evaluation.sh.

1. Run from the blueprint root. Resolve artifact paths to absolute HYPOTHETEST_* variables before invoking helpers.
2. Pass phase commands as separate arguments. Helpers accept declared environment variables and never prompt; missing prerequisites cause non-zero exit.
3. Use structured `[tag] key=value` stdout for helper events. Stream task output to logs while preserving failures and shell state needed by later tasks.
4. Record the variation, repeat, phase, resolved randomized order/seed, start/end times, and artifact paths.
5. Compile an evaluation-index writer for both completion and error paths. Validate its complete and partial outputs against the Operator schema. Index only preserved files; mark incomplete runs honestly.
6. Verify shell syntax, helper existence/executable invocation, and dry-run order before handoff. Dry runs do not prove endpoint access or metric validity.
