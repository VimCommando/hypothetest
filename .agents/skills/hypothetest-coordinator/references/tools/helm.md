# helm

Kubernetes package manager for installing the ECK operator.

## When loaded

When `deployment.target: kubernetes`.

## Install

### macOS
```bash
brew install helm
```

### Linux (Debian/Ubuntu)
```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### Linux (RHEL/Fedora)
```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

## Version check
```bash
helm version --short
```

## Readiness preflight

Verify the Elastic Helm repo is configured and the ECK operator chart is available:
```bash
helm repo list 2>/dev/null | grep -q elastic || helm repo add elastic https://helm.elastic.co
helm repo update elastic
helm search repo elastic/eck-operator --versions | head -3
```

Check whether the ECK operator is already installed:
```bash
helm list -n elastic-system 2>/dev/null | grep -q elastic-operator
```

## References

- https://helm.sh/docs/
- https://github.com/helm/helm
- https://github.com/elastic/cloud-on-k8s (ECK operator Helm chart source)
