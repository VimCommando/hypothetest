# curl

HTTP client for Elasticsearch API access.

## When loaded

Always — every blueprint requires ES API access.

## Install

### macOS
```bash
# Included with macOS. Update via Homebrew if needed:
brew install curl
```

### Linux (Debian/Ubuntu)
```bash
sudo apt-get install -y curl
```

### Linux (RHEL/Fedora)
```bash
sudo dnf install -y curl
```

## Version check
```bash
curl --version
```

## Readiness preflight
```bash
curl -sf "${ELASTICSEARCH_URL}/_cluster/health" -o /dev/null
```

## URL

- https://curl.se/
- https://github.com/curl/curl
