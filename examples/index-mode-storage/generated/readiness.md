# Readiness — index-mode-storage

Checked: 2026-05-02

## Status

**READY WITH WARNINGS** — no blockers. Resolve warnings before first evaluation.

---

## Blockers

None.

---

## Warnings

### W1. `espipe` output format — confirm before first evaluation

`indexing_throughput_docs_per_sec` depends on espipe emitting a structured
runtime summary. The 0.3.0 binary prints a summary to stdout by default
(suppressed with `--quiet`). Confirm the summary includes a docs/sec value
before the first evaluation; if not, the Operator must record it manually in
`espipe_output.json`. See `generated/metrics-plan.yml` for details.

### W2. `espipe` PATH — use explicit binary path

The system PATH resolves `espipe` to the Homebrew 0.2.0 binary
(`/opt/homebrew/bin/espipe`). The Operator must use the full path
`/Users/reno/.cargo/bin/espipe` (or ensure `~/.cargo/bin` precedes
`/opt/homebrew/bin` in PATH) to get the 0.3.0 binary with
`--template`/`--pipeline` support.

```sh
# Verify before evaluation:
/Users/reno/.cargo/bin/espipe --version   # must print 0.3.0
/Users/reno/.cargo/bin/espipe --help | grep template  # must show --template flag
```

---

## Verified

- `podman-compose` **1.5.0** on `ironhide.local` — present and functional
- `espipe` **0.3.0** at `/Users/reno/.cargo/bin/espipe` — present, `--template`/`--pipeline` flags confirmed
- SSH access to `ironhide.local` via `~/.ssh/config` — **ok** (certificate auth, no password)
- Remote user: `reno` (uid=1000, wheel group)
- Remote workdir `/tmp/hypothetest/evaluations` — **writable**, created successfully
- Remote Podman: **5.8.2** — present and functional
- Remote disk space: **1.1 TB free** on `/var` — sufficient
- Dataset: **local** at `datasets/yelp/yelp_academic_dataset_review.json` (5.0 GB) — espipe streams directly to `http://ironhide.local:9200`; no transfer required
- Local `esdiag`: **0.15.0-SNAPSHOT** — present
- Local `curl`: **8.7.1** — present
- Local `jq`: **1.7.1** — present
- Local `toon`: **2.1.0** — present
- No credentials required (security disabled, compose target)

---

## Required Before Operator

| # | Item | Owner |
|---|------|-------|
| 1 | Confirm `espipe` invocations use `/Users/reno/.cargo/bin/espipe` (0.3.0) | operator |

---

## Operator Handoff

```
blueprint:  blueprints/index-mode-storage/blueprint.yml
plan:       blueprints/index-mode-storage/hypothetest.yml
evaluation_guide: blueprints/index-mode-storage/generated/evaluation-guide.md
readiness:  blueprints/index-mode-storage/generated/readiness.md
```
