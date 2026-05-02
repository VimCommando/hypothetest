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
  workdir: /srv/hypothetest/runs
```

The remote SSH username may be declared with `remote.user`. The Coordinator must verify SSH access through the user's `.ssh/config` and permission to run the selected remote compose command before the Operator runs the hypothesis.

Default generated files:

```text
generated/compose/compose.yml
generated/compose/.env
generated/compose/elasticsearch.yml
generated/compose/repositories/
```

Use Elasticsearch filesystem (`fs`) repositories when snapshot repositories are needed. For local compose, mount the repository path into the Elasticsearch container and configure `path.repo`; MinIO is out of scope.

Compose results are development-grade unless the user explicitly calibrates the environment.
