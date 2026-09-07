# Readiness output

## Readiness output

When creating an artifact, write it next to the scenario unless the user requests another path:

```text
generated/readiness.md
generated/readiness.toon
```

Use this Markdown shape:

```markdown
# Readiness

## Status

## Blockers

## Warnings

## Verified

## Required Before Operator

## Operator Handoff
```

Use this TOON shape:

```toon
status: blocked|ready|ready_with_warnings
deployment_target: compose
dataset_loader: espipe
diagnostics_tool: esdiag
blockers[0]:
warnings[0]:
verified[0]:
experiment:
  intent: compare_deployments
  variables[1]: deployment
  constants_required[2]: dataset,workload
  constants_best_effort[1]: index.primary_shards
credential_requirements[1]{name,status,required_for}:
  ELASTICSEARCH_URL,missing,existing deployment
tool_access[1]{tool,required_for,runs_from,status,preflight}:
  esdiag,diagnostics,operator environment,missing,ESDIAG_KEYSTORE_PASSWORD unavailable in nohup environment
os: darwin
tq: verified
observation_packages[2]{name,status,note}:
  elasticsearch_api,verified,http://localhost:9200
  darwin_tools,verified,vm_stat iostat
operator_handoff:
  blueprint: blueprint.yml
  scenario: hypothetest.yml
  readiness: generated/readiness.md
```

For remote compose, include SSH and compose checks in `verified`:

```toon
verified[3]:
  ssh access via ~/.ssh/config host bench-host
  remote docker compose version
  remote workdir writable
```

For remote compose with loader-local data, include a warning or verified note that the raw dataset is loaded through the indexing tool and is not staged to the SSH host.


For pending target checks, record the provisioning task, check command, required context, and pre-load gate. A generated gate is pending evidence until it actually passes. See [readiness decisions](execution-contract.md#readiness-decisions).
