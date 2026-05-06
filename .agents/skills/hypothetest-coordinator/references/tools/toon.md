# toon

Structured summary output format and CLI tool.

## When loaded

Always — readiness.toon, manifest.toon, and observation outputs use TOON format.

## Install

### Cargo
```bash
cargo install toon
```

## Version check
```bash
toon --version
```

## Readiness preflight
```bash
echo 'status: ok' | toon validate -
```

## URL
https://crates.io/crates/toon
