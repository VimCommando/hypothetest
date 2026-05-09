# esdiag

Elasticsearch diagnostic collector — captures cluster state snapshots
via configurable API lists.

## When loaded

When `measure.diagnostics.tool: esdiag` in the blueprint.

## Install

### Cargo
```bash
cargo install esdiag
```

## Version check
```bash
esdiag --version
```

## Readiness preflight

Register the cluster as a named host and verify collection works:
```bash
esdiag host add myhost elasticsearch "${ELASTICSEARCH_URL}"
esdiag collect myhost /tmp/esdiag-preflight
unzip -q -o /tmp/esdiag-preflight/*.zip -d /tmp/esdiag-preflight/out
test -f /tmp/esdiag-preflight/out/nodes_stats.json
```

`esdiag collect` requires a named host, not a raw URL. See
[`../../../hypothetest-operator/references/esdiag-operations.md`](../../../hypothetest-operator/references/esdiag-operations.md) for full syntax.

When an encrypted keystore is configured, verify the keystore password
source is available:
```bash
test -n "${ESDIAG_KEYSTORE_PASSWORD:-}"
```

## URL

- https://github.com/elastic/esdiag
- https://crates.io/crates/esdiag
