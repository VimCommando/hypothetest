# k3s

Lightweight Kubernetes distribution for local hypothetest deployments.
Bundles kubectl, containerd, and a single-node cluster in one binary.

## When loaded

When `deployment.kubernetes.provider` resolves to `k3s`.

Not loaded when provider is `existing` — the user already has a
Kubernetes cluster and doesn't need k3s context.

## Install

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik --disable servicelb" sh -
```

This installs k3s as a system service (systemd on Linux). Traefik and
ServiceLB are disabled to reduce resource contention during benchmarks —
hypothetest uses `kubectl port-forward` for ES access, not ingress.
After install, kubectl is available at `/usr/local/bin/kubectl` via symlink.

Verify:
```bash
kubectl cluster-info
kubectl get nodes
```

For environments where the k3s kubeconfig needs to be exported:
```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```

## Version check
```bash
k3s --version
```

## Readiness preflight

Verify k3s is running and the node is ready:
```bash
systemctl is-active k3s
kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' | grep -q True
```

## Uninstall

k3s ships its own uninstall script. Clean removal:
```bash
/usr/local/bin/k3s-uninstall.sh
```

This removes the k3s binary, systemd service, all containers, all data,
and the kubeconfig. The machine is returned to pre-install state.

## References

- https://docs.k3s.io/
- https://github.com/k3s-io/k3s
