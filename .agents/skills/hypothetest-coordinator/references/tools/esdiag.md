# esdiag

Elasticsearch diagnostic collector — captures cluster state snapshots from
saved hosts.

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

Register the Elasticsearch endpoint as a saved host before Operator execution:
```bash
esdiag host add "${ESDIAG_HOST:-hypothetest-local}" "${ELASTICSEARCH_URL}" --app elasticsearch
```

Verify esdiag can collect from the saved host into an existing directory:
```bash
mkdir -p /tmp/hypothetest-esdiag-preflight
esdiag collect "${ESDIAG_HOST:-hypothetest-local}" /tmp/hypothetest-esdiag-preflight --type standard
```

When an encrypted keystore is configured, verify the keystore password
source is available:
```bash
test -n "${ESDIAG_KEYSTORE_PASSWORD:-}"
```

## Command shape

`esdiag collect` uses positional arguments:

```text
esdiag collect [OPTIONS] <HOST> <OUTPUT>
```

`<HOST>` is a saved host name, not a raw URL. `<OUTPUT>` is an existing
directory, not a zip filename. Prefer `--type standard` for Hypothetest
diagnostics. Do not generate `--host`, `--output`, or `--apis` flags. If
API filtering is needed, `--include` accepts esdiag internal API identifiers,
not raw Elasticsearch paths.

## URL

- https://github.com/elastic/esdiag
- https://crates.io/crates/esdiag
