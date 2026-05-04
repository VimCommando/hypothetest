# Compose Target

`compose` is the first implementation target and should be treated as first-class.

Goals:

- Fast local iteration.
- Docker or Podman support.
- Deterministic generated assets.
- Useful workflow validation before remote deployments exist.

Engine values:

```yaml
scope: local | remote
engine: auto | docker | podman
```

Remote compose MVP uses SSH certificate-based auth:

```yaml
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

The remote SSH username may be declared with `remote.user`. The Coordinator must verify SSH access through the user's `.ssh/config` and permission to execute the selected remote compose command before the Operator evaluates the hypothesis.

Remote compose separates the control plane from the data plane:

- SSH is used to create, reset, and manage the remote compose deployment.
- Raw benchmark data is not copied to the SSH host by default.
- Dataset loading is performed by the declared loader, such as `espipe` or Rally/esrally, against the Elasticsearch endpoint exposed by the deployment.
- Local input files, Rally tracks, and espipe inputs stay on the loader machine unless the blueprint explicitly declares remote data generation or a remote-local phase script.
- `deployment.remote.workdir` stores generated compose assets, runtime support files, logs, and manifests, not the raw corpus by default.

Default generated files:

```text
generated/compose/compose.yml
generated/compose/.env
generated/compose/elasticsearch.yml
generated/compose/repositories/
```

Use Elasticsearch filesystem (`fs`) repositories when snapshot repositories are needed. For local compose, mount the repository path into the Elasticsearch container and configure `path.repo`; MinIO is out of scope.

Compose results are development-grade unless the user explicitly calibrates the environment.
