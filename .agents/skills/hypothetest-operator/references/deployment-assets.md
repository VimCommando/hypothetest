# Deployment assets

Read the sections for every declared deployment target.

## Compose engine handling

Accept:

```yaml
deployment:
  target: compose
  scope: local | remote
  engine: auto | docker | podman
```

Resolution order when `engine: auto`:

1. Prefer `docker compose` if available.
2. Else use `podman compose` if available.
3. Else use `podman-compose` if available.
4. Else fail with installation instructions.

Do not assume Docker is present.

For `scope: remote`, apply the [readiness decision table](../../hypothetest-coordinator/references/execution-contract.md#readiness-decisions) before execution. The remote host must be reachable through the user's `.ssh/config` using SSH certificate auth, and the remote user must be able to execute the resolved compose command:

- `docker compose version` for Docker.
- `podman compose version` or `podman-compose --version` for Podman.

Execute compose operations on the remote host in the declared `deployment.remote.workdir`.

For remote compose, treat SSH as the deployment control plane, not the dataset transport. Do not copy raw corpus files to `deployment.remote.workdir` by default. Load data through the declared indexing/workload tool, such as `espipe` or Rally/esrally, against the Elasticsearch endpoint exposed by the remote deployment. Only stage raw data on the remote host when the blueprint explicitly declares remote data generation, a remote download, or a remote-local phase script.

## Compose assets

The Coordinator generates compose infrastructure. The Operator consumes it
via `generated/scripts/compose-up.sh` and `compose-down.sh`. Expected layout:

```text
generated/compose/compose.yml
generated/compose/.env
generated/compose/elasticsearch.yml
generated/compose/repositories/
generated/compose/volumes/
```

The Operator does not generate or modify these assets.

## Kubernetes assets

The Coordinator generates kubernetes infrastructure. The generated runner
calls `eck-up.sh` and `eck-down.sh` as lifecycle tasks, matching the compose
convention (`compose_up` / `compose_down`). The runner passes the baseline
variation to `eck-up.sh` via `HYPOTHETEST_VARIATION` and tracks
`CURRENT_VARIATION` so `apply_variation` skips the redundant first apply.

When the provider is k3s, `k3s-install.sh` and `k3s-uninstall.sh` handle
the cluster lifecycle independently of ECK. Expected layout:

```text
generated/eck/namespace.yaml
generated/eck/elasticsearch.yaml
generated/eck/kibana.yaml          (only when services.kibana: true)
generated/scripts/eck-up.sh
generated/scripts/eck-down.sh
generated/scripts/k3s-install.sh   (only when provider: k3s)
generated/scripts/k3s-uninstall.sh (only when provider: k3s)
```

The Operator does not generate or modify these assets.
