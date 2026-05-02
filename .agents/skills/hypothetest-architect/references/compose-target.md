# Compose Target

`compose` is the first implementation target and should be treated as first-class.

Goals:

- Fast local iteration.
- Docker or Podman support.
- Deterministic generated assets.
- Useful workflow validation before remote deployments exist.

Engine values:

```yaml
engine: auto | docker | podman
```

Default generated files:

```text
generated/compose/compose.yml
generated/compose/.env
generated/compose/elasticsearch.yml
generated/compose/repositories/
```

Use Elasticsearch filesystem (`fs`) repositories when snapshot repositories are needed. For local compose, mount the repository path into the Elasticsearch container and configure `path.repo`; MinIO is out of scope.

Compose results are development-grade unless the user explicitly calibrates the environment.
