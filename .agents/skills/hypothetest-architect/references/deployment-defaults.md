# Deployment defaults

Read the section for each declared target. For Compose engine and repository details, also read [compose-target.md](compose-target.md).

## Compose defaults

When target is `compose`, use these defaults unless overridden:

```yaml
deployment:
  target: compose
  scope: local
  engine: auto
  elasticsearch:
    version: latest
    nodes: 1
    security: false
    heap: 2g
    memory: 4g
  services:
    kibana: false
  repositories:
    bench-repo:
      type: fs
      location: /usr/share/elasticsearch/snapshots/bench-repo
```

For local compose snapshot, searchable snapshot, frozen-like, or repository behavior, use Elasticsearch filesystem (`fs`) repositories mounted into the Elasticsearch container. MinIO and S3-compatible services are out of scope for local compose.

Compose output should be marked development-grade in generated report guidance and operator guidance.

Compose can execute locally or on a remote host:

```yaml
deployment:
  target: compose
  scope: remote
  engine: docker
  remote:
    host: bench-host
    user: benchmark
    auth:
      method: ssh_certificate
      ssh_config_host: bench-host
    workdir: /srv/hypothetest/evaluations
```

For MVP remote compose, only SSH certificate-based auth through the user's `.ssh/config` is supported. `deployment.remote.user` may specify the remote SSH username, but do not put identity or certificate file paths in `hypothetest.yml`; the Coordinator validates SSH access and remote permission to execute the selected compose engine before Operator execution.

Remote compose SSH controls the deployment host only. Do not imply that raw dataset files are copied to `deployment.remote.workdir`. Dataset ingestion still happens through the declared loader, such as `espipe` or Rally/esrally, against the Elasticsearch endpoint exposed by the deployment. Only generated compose assets, operator scripts, runtime manifests, and deployment support files belong on the remote SSH host unless the blueprint explicitly declares a remote-generated fixture or remote-local phase script.

## Kubernetes defaults

When target is `kubernetes`, use these defaults unless overridden:

```yaml
deployment:
  target: kubernetes
  namespace: hypothetest
  elasticsearch:
    version: latest
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

When `kubernetes.provider` is omitted, the Coordinator detects whether a
cluster exists and asks the user before acting. Explicit `provider: k3s`
or `provider: existing` skips the question.

Kubernetes output should be marked development-grade when running on k3s
or similar lightweight distributions. The Coordinator generates CRD
manifests in `generated/eck/` and lifecycle scripts (`eck-up.sh`,
`eck-down.sh`) that follow the same calling convention contract as
compose scripts.
