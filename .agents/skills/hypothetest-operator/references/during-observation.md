# During-phase observation

Read when measure.diagnostics.during is active.

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
