# jq

Lightweight JSON processor for signal extraction in generated scripts.

## When loaded

When `diagnostics.during` is declared — sample.sh uses jq to extract
signals from ES API JSON responses.

## Install

### macOS
```bash
brew install jq
```

### Linux (Debian/Ubuntu)
```bash
sudo apt-get install -y jq
```

### Linux (RHEL/Fedora)
```bash
sudo dnf install -y jq
```

## Version check
```bash
jq --version
```

## Readiness preflight
```bash
echo '{"status":"green"}' | jq -r '.status'
```

## URL
https://jqlang.github.io/jq/
