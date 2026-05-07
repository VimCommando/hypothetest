# kubectl

Kubernetes CLI for managing ECK-deployed Elasticsearch clusters.

## When loaded

When `deployment.target: kubernetes`.

## Install

kubectl is provided by the Kubernetes distribution. When provider is
`k3s`, kubectl is bundled with the k3s install. When provider is
`existing`, kubectl must already be configured for the target cluster.

## Version check
```bash
kubectl version --client
```

## Readiness preflight

Verify cluster access and that the ECK CRDs are available:
```bash
kubectl cluster-info >/dev/null 2>&1
kubectl get crd elasticsearches.elasticsearch.k8s.elastic.co >/dev/null 2>&1
```

Check that the target namespace exists or can be created:
```bash
kubectl get namespace hypothetest >/dev/null 2>&1
```

## References

- https://kubernetes.io/docs/reference/kubectl/
- https://github.com/kubernetes/kubectl
