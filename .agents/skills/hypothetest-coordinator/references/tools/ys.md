# ys

YAML schema validator from the yaml-schema Rust crate.

## When loaded

Always — schema validation of hypothetest.yml and blueprint.yml.

## Install

### Cargo
```bash
cargo install yaml-schema
```

## Version check
```bash
ys --version
```

## Readiness preflight
```bash
echo 'name: test' | ys --schema /dev/null -
```

## URL

- https://github.com/yaml-schema/yaml-schema
- https://crates.io/crates/yaml-schema
