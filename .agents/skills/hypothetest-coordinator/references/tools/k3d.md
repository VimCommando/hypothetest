# k3d

k3s-in-Docker — runs a k3s Kubernetes cluster inside Docker containers.
Works on macOS and Linux without requiring systemd or native binaries.

## When loaded

When `deployment.kubernetes.provider` resolves to `k3d`.

Not loaded when provider is `existing` or `k3s`.

## Prerequisites

Docker must be installed and running. k3d creates and manages Docker
containers that each run k3s.

```bash
docker info >/dev/null 2>&1
```

## Install

### macOS
```bash
brew install k3d
```

### Linux
```bash
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
```

## Version check
```bash
k3d version
```

## Readiness preflight

Verify Docker is running and k3d is installed:
```bash
docker info >/dev/null 2>&1
k3d version
```

## Cluster lifecycle

### Create

```bash
k3d cluster create hypothetest \
  --agents 0 \
  --port "9200:9200@server:0" \
  --k3s-arg "--disable=traefik@server:0" \
  --k3s-arg "--disable=servicelb@server:0"
```

Single server node, no agent nodes. Traefik and ServiceLB disabled to
reduce resource contention during benchmarks. Port 9200 mapped for
direct Elasticsearch access without port-forward.

### Kubeconfig

```bash
k3d kubeconfig merge hypothetest --kubeconfig-merge-default
```

Merges the cluster kubeconfig into `~/.kube/config`. The context is
named `k3d-hypothetest`.

### Delete

```bash
k3d cluster delete hypothetest
```

Removes containers, volumes, and network. The kubeconfig context is
automatically cleaned up by k3d.

## Differences from k3s

| | k3s | k3d |
|---|---|---|
| Platform | Linux only (systemd) | macOS + Linux (Docker) |
| Install | System binary + service | Docker containers |
| Cleanup | `/usr/local/bin/k3s-uninstall.sh` | `k3d cluster delete` |
| Kubeconfig | `/etc/rancher/k3s/k3s.yaml` | `k3d kubeconfig` |
| Isolation | System-level | Container-level (multiple clusters can coexist) |

## References

- https://k3d.io/
- https://github.com/k3d-io/k3d
