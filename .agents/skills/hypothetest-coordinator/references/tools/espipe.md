# espipe

Rust CLI for bulk-loading NDJSON/CSV data into Elasticsearch.

## When loaded

When `dataset.loader: espipe` in the blueprint.

## Install

### Cargo
```bash
cargo install espipe
```

## Version check
```bash
espipe --version
```

## Readiness preflight
```bash
espipe --help >/dev/null
```

Verify `--template` and `--pipeline` flags are available (required for
variation-specific index template and ingest pipeline application):
```bash
espipe --help | grep -q -- '--template'
```

## URL
https://crates.io/crates/espipe
