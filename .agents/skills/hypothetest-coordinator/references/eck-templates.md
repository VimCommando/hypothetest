# ECK Templates

Pattern catalog for generating ECK infrastructure assets. The Coordinator
reads `readiness.toon` and the blueprint's deployment block, then adapts
these patterns to produce `generated/eck/` manifests.

This is a pattern catalog: complete, annotated examples the Coordinator
adapts per experiment. Not parameterized `{{variable}}` templates.

Design influenced by the kustomize base/overlay pattern from
[eck-kittyhawk](https://github.com/jdel12/eck-kittyhawk): base CRD
manifests carry sensible defaults, and experiment-specific values (node
count, heap, storage, version) are adaptation points the Coordinator
fills from the blueprint's deployment block. When an experiment declares
multiple variations, the Coordinator generates a kustomize base/overlay
structure so each variation is an isolated, reproducible manifest patch.

## Input contract

Two inputs drive ECK generation decisions:

**readiness.toon** — what's available on the target platform:
```toon
deployment_target: kubernetes
kubernetes: verified
kubectl: verified
helm: verified
eck_operator: installed
namespace: hypothetest
```

**deployment block** from hypothetest.yml — what the blueprint declares:
```yaml
deployment:
  target: kubernetes
  namespace: hypothetest
  elasticsearch:
    version: 9.0.0
    nodes: 1
    storage: 10Gi
    security: false
    heap: 2g
    memory: 4g
  services:
    kibana: false
  kubernetes:
    operator_version: 3.3.2
    install_operator: true
```

Generation rules:
- All versions come from the blueprint declaration — never hardcode
- Generate manifests only for declared services (skip Kibana CRD when `services.kibana: false`)
- Namespace comes from `deployment.namespace` (default: `hypothetest`)
- When `security: false`, disable TLS and create a plaintext HTTP service
- When `storage` is declared, generate volumeClaimTemplates
- When `kubernetes.install_operator: false`, skip operator installation (assume pre-existing)

## Generated output layout

```
generated/eck/
  namespace.yaml
  elasticsearch.yaml
  kibana.yaml              # only when services.kibana: true
```

The Coordinator also generates `generated/scripts/eck-up.sh` and
`generated/scripts/eck-down.sh` (lifecycle scripts, documented separately).

## ECK operator installation

Helm-based installation. The Coordinator generates the helm commands into
`eck-up.sh` when `deployment.kubernetes.install_operator: true`.

```bash
helm repo add elastic https://helm.elastic.co
helm repo update elastic
helm install elastic-operator elastic/eck-operator \
  --namespace elastic-system \
  --create-namespace \
  --version "${ECK_OPERATOR_VERSION}"
```

Wait for operator readiness before applying CRDs:
```bash
kubectl wait --for=condition=Available \
  deployment/elastic-operator -n elastic-system \
  --timeout=120s
```

When the operator is already installed (`install_operator: false`), skip
the helm install and verify the operator is running:
```bash
kubectl get deployment elastic-operator -n elastic-system -o jsonpath='{.status.availableReplicas}' | grep -q '[1-9]'
```

## Trial license

Apply an enterprise trial license only when the blueprint explicitly
declares it under `deployment.kubernetes.license`. This enables all ECK
features (monitoring, autoscaling, advanced configuration) without
requiring a paid license.

```yaml
# In hypothetest.yml:
deployment:
  kubernetes:
    license:
      type: enterprise_trial
      accept_eula: true
```

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: eck-trial-license
  namespace: elastic-system
  labels:
    license.k8s.elastic.co/type: enterprise_trial
  annotations:
    elastic.co/eula: accepted
```

In `eck-up.sh`, gate behind `HYPOTHETEST_APPLY_TRIAL_LICENSE=true`.
When the blueprint declares a license, the Coordinator sets this env var
in the generated script. When absent, skip with a log message.

## Namespace pattern

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: hypothetest
```

The namespace name comes from `deployment.namespace`. Applied before any
CRDs so the target namespace exists.

## Elasticsearch CRD patterns

### Single-node, security disabled

Disables TLS and security. Uses a privileged initContainer to set
`vm.max_map_count=1048576` — required for benchmark-grade mmap
performance. Never use `node.store.allow_mmap: false` for benchmarks;
it disables memory mapping and degrades I/O throughput.

```yaml
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: hypothetest
  namespace: hypothetest
spec:
  version: 9.0.0
  http:
    tls:
      selfSignedCertificate:
        disabled: true
  nodeSets:
  - name: default
    count: 1
    config:
      xpack.security.enabled: false
      xpack.security.http.ssl.enabled: false
      xpack.security.transport.ssl.enabled: false
    podTemplate:
      spec:
        initContainers:
        - name: sysctl
          securityContext:
            privileged: true
            runAsUser: 0
          command: ['sh', '-c', 'sysctl -w vm.max_map_count=1048576']
        containers:
        - name: elasticsearch
          env:
          - name: ES_JAVA_OPTS
            value: "-Xms2g -Xmx2g"
          resources:
            requests:
              memory: 4Gi
            limits:
              memory: 4Gi
    volumeClaimTemplates:
    - metadata:
        name: elasticsearch-data
      spec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: 10Gi
```

Adaptation points:
- `spec.version` from `deployment.elasticsearch.version`
- `nodeSets[0].count` from `deployment.elasticsearch.nodes`
- `ES_JAVA_OPTS` from `deployment.elasticsearch.heap`
- `resources.requests.memory` / `limits.memory` from `deployment.elasticsearch.memory`
- `storage` from `deployment.elasticsearch.storage`
- When `deployment.elasticsearch.storage` is omitted, omit the
  `volumeClaimTemplates` block entirely (ECK defaults to 1Gi emptyDir-like PVC)

### vm.max_map_count — initContainer

Elasticsearch requires `vm.max_map_count=1048576` (ES 8.16+). Always
use a privileged initContainer to set this kernel parameter at pod
startup. For benchmarking, never use `node.store.allow_mmap: false` —
it disables memory-mapped file access and invalidates performance
measurements.

```yaml
podTemplate:
  spec:
    initContainers:
    - name: sysctl
      securityContext:
        privileged: true
        runAsUser: 0
      command: ['sh', '-c', 'sysctl -w vm.max_map_count=1048576']
```

When readiness.toon reports `vm_max_map_count: verified` (host already
configured), the initContainer can be omitted.

### Single-node, security enabled

When `deployment.elasticsearch.security: true` (or omitted — ECK default
is security enabled). TLS is active, credentials are auto-generated.

```yaml
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: hypothetest
  namespace: hypothetest
spec:
  version: 9.0.0
  nodeSets:
  - name: default
    count: 1
    podTemplate:
      spec:
        initContainers:
        - name: sysctl
          securityContext:
            privileged: true
            runAsUser: 0
          command: ['sh', '-c', 'sysctl -w vm.max_map_count=1048576']
        containers:
        - name: elasticsearch
          env:
          - name: ES_JAVA_OPTS
            value: "-Xms2g -Xmx2g"
          resources:
            requests:
              memory: 4Gi
            limits:
              memory: 4Gi
    volumeClaimTemplates:
    - metadata:
        name: elasticsearch-data
      spec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: 10Gi
```

With security enabled, the `elastic` user password is auto-generated in
a Kubernetes secret: `hypothetest-es-elastic-user`. The Coordinator's
`eck-up.sh` retrieves it for `ELASTICSEARCH_URL` construction.

Password retrieval:
```bash
kubectl get secret hypothetest-es-elastic-user -n hypothetest \
  -o go-template='{{.data.elastic | base64decode}}'
```

### Multi-node

When `deployment.elasticsearch.nodes > 1`. Each node gets its own PVC.

```yaml
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: hypothetest
  namespace: hypothetest
spec:
  version: 9.0.0
  nodeSets:
  - name: default
    count: 3
    config:
      xpack.security.enabled: false
      xpack.security.http.ssl.enabled: false
      xpack.security.transport.ssl.enabled: false
    podTemplate:
      spec:
        initContainers:
        - name: sysctl
          securityContext:
            privileged: true
            runAsUser: 0
          command: ['sh', '-c', 'sysctl -w vm.max_map_count=1048576']
        containers:
        - name: elasticsearch
          env:
          - name: ES_JAVA_OPTS
            value: "-Xms2g -Xmx2g"
          resources:
            requests:
              memory: 4Gi
            limits:
              memory: 4Gi
    volumeClaimTemplates:
    - metadata:
        name: elasticsearch-data
      spec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: 10Gi
```

For multi-node clusters, the Coordinator should set pod anti-affinity to
spread nodes across Kubernetes hosts when possible:
```yaml
podTemplate:
  spec:
    affinity:
      podAntiAffinity:
        preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          podAffinityTerm:
            labelSelector:
              matchLabels:
                elasticsearch.k8s.elastic.co/cluster-name: hypothetest
            topologyKey: kubernetes.io/hostname
```

### Tiered node roles

When the blueprint declares multiple nodeSets with explicit `node.roles`,
the Coordinator generates separate nodeSet entries. Relevant for storage
tiering experiments (hot/cold), dedicated ingest, or separated
coordinator nodes.

```yaml
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: hypothetest
  namespace: hypothetest
spec:
  version: 9.0.0
  nodeSets:
  - name: hot
    count: 2
    config:
      node.roles: ["master", "data_hot", "data_content", "ingest"]
      xpack.security.enabled: false
      xpack.security.http.ssl.enabled: false
      xpack.security.transport.ssl.enabled: false
    podTemplate:
      spec:
        containers:
        - name: elasticsearch
          env:
          - name: ES_JAVA_OPTS
            value: "-Xms2g -Xmx2g"
          resources:
            requests:
              memory: 4Gi
            limits:
              memory: 4Gi
    volumeClaimTemplates:
    - metadata:
        name: elasticsearch-data
      spec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: 20Gi
  - name: cold
    count: 1
    config:
      node.roles: ["data_cold"]
      xpack.security.enabled: false
      xpack.security.http.ssl.enabled: false
      xpack.security.transport.ssl.enabled: false
    podTemplate:
      spec:
        containers:
        - name: elasticsearch
          env:
          - name: ES_JAVA_OPTS
            value: "-Xms1g -Xmx1g"
          resources:
            requests:
              memory: 2Gi
            limits:
              memory: 2Gi
    volumeClaimTemplates:
    - metadata:
        name: elasticsearch-data
      spec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: 50Gi
```

Each nodeSet can have its own resource profile, storage size, and
storageClassName. The Coordinator generates nodeSet entries from the
blueprint's deployment topology — the number and shape of nodeSets is
driven by the experiment, not hardcoded.

## Kibana CRD pattern

Generated only when `deployment.services.kibana: true`.

```yaml
apiVersion: kibana.k8s.elastic.co/v1
kind: Kibana
metadata:
  name: hypothetest
  namespace: hypothetest
spec:
  version: 9.0.0
  count: 1
  elasticsearchRef:
    name: hypothetest
```

`spec.version` matches the Elasticsearch version from the blueprint.

## StorageClass pattern

Only needed when the target Kubernetes cluster's default StorageClass
doesn't meet experiment requirements (e.g., specific provisioner, IOPS
class, filesystem type).

Most k3s and managed Kubernetes environments have a usable default
StorageClass. The Coordinator generates a StorageClass manifest only
when the blueprint explicitly declares one:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: hypothetest-storage
provisioner: rancher.io/local-path
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
```

When generated, reference it in the Elasticsearch volumeClaimTemplates:
```yaml
storageClassName: hypothetest-storage
```

## Service exposure patterns

ECK automatically creates a ClusterIP service for Elasticsearch:
`<cluster-name>-es-http` on port 9200. For local access, port-forward:

```bash
kubectl port-forward -n hypothetest service/hypothetest-es-http 9200:9200
```

The generated `eck-up.sh` starts a background port-forward after the
cluster is healthy, so `ELASTICSEARCH_URL=http://localhost:9200` works
from the evaluation host.

For security-disabled clusters:
```
ELASTICSEARCH_URL=http://localhost:9200
```

For security-enabled clusters:
```
ELASTICSEARCH_URL=https://localhost:9200
ELASTICSEARCH_USERNAME=elastic
ELASTICSEARCH_PASSWORD=$(kubectl get secret hypothetest-es-elastic-user -n hypothetest -o go-template='{{.data.elastic | base64decode}}')
```

## Readiness signals driving CRD generation

The Coordinator reads `readiness.toon` to make generation decisions:

| Readiness signal | CRD generation decision |
|---|---|
| `kubernetes: verified` | Proceed with ECK target |
| `kubectl: verified` | Can apply manifests |
| `helm: verified` | Can install ECK operator |
| `eck_operator: installed` | Skip operator install, verify running |
| `eck_operator: missing` | Include operator install in eck-up.sh |
| `namespace: <name>` | Use declared namespace in all manifests |
| `storage_class: <name>` | Set storageClassName in volumeClaimTemplates |
| `vm_max_map_count: verified` | Omit sysctl initContainer |
| `vm_max_map_count: unverified` | Include sysctl initContainer (`vm.max_map_count=1048576`) |

## Kustomize variation patterns

When a blueprint declares multiple variations that change Kubernetes
resource values (heap, memory, node count, storage, node roles), the
Coordinator generates a kustomize base/overlay structure. This keeps
the common CRD shape in one place and isolates variation-specific
changes to small, reviewable patches.

Reference: [eck-kittyhawk](https://github.com/jdel12/eck-kittyhawk)
demonstrates this pattern for production ECK deployments.

### Generated layout

```
generated/eck/
  base/
    kustomization.yaml
    elasticsearch.yaml
    namespace.yaml
  overlays/
    <variation-name>/
      kustomization.yaml
      patch.yaml
```

### Base kustomization

The base contains the full CRD with the blueprint's baseline values.
`kustomization.yaml` simply lists the resources:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - elasticsearch.yaml
```

### Overlay pattern

Each variation overlay patches only the fields that differ. The overlay
`kustomization.yaml` references the base and applies a strategic merge
patch:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
patches:
  - path: patch.yaml
```

### Patch examples

**Heap and memory variation** (the most common case):
```yaml
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: hypothetest
  namespace: hypothetest
spec:
  nodeSets:
  - name: default
    podTemplate:
      spec:
        containers:
        - name: elasticsearch
          env:
          - name: ES_JAVA_OPTS
            value: "-Xms4g -Xmx4g"
          resources:
            requests:
              memory: 8Gi
            limits:
              memory: 8Gi
```

**Node count variation**:
```yaml
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: hypothetest
  namespace: hypothetest
spec:
  nodeSets:
  - name: default
    count: 3
```

The patch shape mirrors the base CRD — only the fields being varied
are present. The Coordinator derives patch content from
`variations.<name>.config` in the blueprint.

### Applying variations

The evaluation runner applies each variation with:

```bash
kustomize build generated/eck/overlays/${VARIATION} | kubectl apply -f -
```

Then waits for the cluster to reach green health before proceeding:

```bash
kubectl wait --for=jsonpath='{.status.health}'=green \
  elasticsearch/hypothetest -n hypothetest \
  --timeout=300s
```

After a variation completes (load, capture, diagnostics), the runner
either:
- Applies the next overlay (which triggers a rolling update), or
- Tears down and recreates (when the variation changes are too
  disruptive for a rolling update, e.g., storage class changes)

The Coordinator decides which strategy to use based on the variation
fields. Heap and memory changes support rolling updates. Storage,
node role, and node count changes typically require teardown/recreate.

### Variation cycling contract

The evaluation runner for Kubernetes follows this loop:

```
for each variation:
  1. kustomize build overlays/<variation> | kubectl apply
  2. wait for cluster health green
  3. run load phase
  4. capture metrics and diagnostics
  5. reset index (if not last variation)
```

The Coordinator generates this runner as `generated/scripts/evaluation.sh`
with the same structure as compose evaluation runners — same task
functions, same artifact contract, same log tag conventions.
