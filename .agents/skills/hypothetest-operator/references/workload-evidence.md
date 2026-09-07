# Workload evidence

Read for each dataset loader and phase tool in the plan. Execute only Coordinator-resolved commands and preserve their outputs.

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

Invoke Rally through `ESRALLY_BIN` when provided so background wrappers do not
depend on an interactive shell `PATH`. For `esrally race`, use
`--report-format=markdown` and `--report-file`; do not use nonexistent
`--results-format` or `--results-file` flags. Add
`--kill-running-processes` to race invocations to clear stale Rally PID
registrations after interrupted runs.

For ingest-only comparisons, prefer an index-only challenge such as
`append-no-conflicts-index-only` when available. The full
`append-no-conflicts` challenge includes query tasks that can dominate runtime
and heap requirements.

If a track corpus is pre-seeded, do it before any Rally process starts and
write to Rally's actual `local.dataset.cache` path from `rally.ini`. Never
copy corpus files into Rally's data directory while Rally is running.

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
- response body in its original format; derive TOON measurements separately

For `shell` and `python`, use only repo-local scripts or explicitly allowlisted paths.

Never execute arbitrary inline shell or Python from the scenario. A phase must reference a file that is either repo-local or matched by an allowlist in the canonical plan.
