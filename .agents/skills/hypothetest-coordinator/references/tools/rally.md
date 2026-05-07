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
esrally --version
```

## Readiness preflight

Verify Rally can resolve its configuration and reach the cluster:
```bash
esrally list tracks --target-hosts="${ELASTICSEARCH_URL}" 2>/dev/null
```

## URL

- https://esrally.readthedocs.io/
- https://github.com/elastic/rally
