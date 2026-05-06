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

Verify esdiag can reach the cluster:
```bash
esdiag collect --host "${ELASTICSEARCH_URL}" --apis "_cluster/health" --dry-run
```

When an encrypted keystore is configured, verify the keystore password
source is available:
```bash
test -n "${ESDIAG_KEYSTORE_PASSWORD:-}"
```

## URL
https://crates.io/crates/esdiag
