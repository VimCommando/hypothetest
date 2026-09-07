# rally

Elasticsearch benchmarking tool for track/challenge-oriented workloads.

## When loaded

When `dataset.loader: rally` in the blueprint.

## Install

### macOS
```bash
pip3 install esrally
```

### Linux (Debian/Ubuntu)
```bash
pip3 install esrally
```

### Linux (RHEL/Fedora)
```bash
pip3 install esrally
```

## Version check
```bash
"${ESRALLY_BIN:-esrally}" --version
```

## Readiness preflight

Verify Rally can resolve its configuration and reach the cluster:
```bash
"${ESRALLY_BIN:-esrally}" list tracks --target-hosts="${ELASTICSEARCH_URL}" 2>/dev/null
```

For background, `nohup`, or `caffeinate` runs, readiness must verify the exact
binary path that the Operator will use. Prefer exporting `ESRALLY_BIN` to the
full path, for example `/Users/reno/.local/bin/esrally` for pipx installs.

## Corpus cache

Rally downloads track corpus data on the first `esrally race`; `esrally
download` downloads Elasticsearch distributions and does not pre-fetch track
data. If a blueprint needs predictable runtime, the Coordinator should
pre-seed corpus files with `curl` before Operator execution and with no Rally
processes running.

Resolve the actual cache directory from Rally configuration. In common pipx
setups, `CONFIG_DIR` may be `~/.rally/.rally`, making the cache:

```text
~/.rally/.rally/benchmarks/data/<track>/
```

Do not assume `~/.rally/benchmarks/data/`.

For the public `http_logs` track, pre-download resumably:

```bash
BASE="https://rally-tracks.elastic.co/http_logs"
RALLY_DATA_DIR="${RALLY_DATA_DIR:-$HOME/.rally/.rally/benchmarks/data/http_logs}"
mkdir -p "${RALLY_DATA_DIR}"
cd "${RALLY_DATA_DIR}"
for f in documents-181998.json.bz2 documents-191998.json.bz2 \
          documents-201998.json.bz2 documents-211998.json.bz2 \
          documents-221998.json.bz2 documents-231998.json.bz2; do
    curl -fsSL -C - -o "$f" "${BASE}/${f}" &
done
wait
curl -fL -C - -o documents-241998.json.bz2 "${BASE}/documents-241998.json.bz2"
```

Never copy or modify corpus files while Rally is running. If a download was
interrupted or corrupted, stop Rally processes first, remove the track data
directory, and re-download cleanly.

## Race invocation

`esrally race` does not support `--results-format` or `--results-file`. Use
`--report-format=markdown` and `--report-file=<path>` for the report artifact,
and rely on the Rally metrics store or Analyst parsing for machine-readable
metrics.

Always include `--kill-running-processes` to clear stale Rally PID registry
entries after crashes. For ingest-only benchmarks on `http_logs`, prefer:

```bash
"${ESRALLY_BIN:-esrally}" race \
  --pipeline=benchmark-only \
  --track=http_logs \
  --challenge=append-no-conflicts-index-only \
  --target-hosts="${ELASTICSEARCH_URL#http://}" \
  --kill-running-processes \
  --report-format=markdown \
  --report-file="${report_file}"
```

The full `append-no-conflicts` challenge includes query and force-merge work
after ingest; use it only when those operations are part of the hypothesis.

## URL

- https://esrally.readthedocs.io/
- https://github.com/elastic/rally
