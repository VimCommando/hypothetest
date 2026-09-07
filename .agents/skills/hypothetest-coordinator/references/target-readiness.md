# Target readiness

Reuse the target and execution boundaries already authorized in the session. Ask only when the host, deployment, destructive scope, or cost boundary remains unresolved or changes. Confirm technical facts with checks rather than asking the user to repeat them.

## Scenario-specific checks

For `compose`:

- Verify at least one compose engine path exists: `docker compose`, `podman compose`, or `podman-compose`.
- If `deployment.scope` is `remote`, echo the target before acting: "Deploying to `<ssh_config_host>` at `<workdir>`. Is this the right host?" Confirm before proceeding.
- If `deployment.scope` is `remote`, validate SSH access to `deployment.remote.auth.ssh_config_host` using the user's `.ssh/config`, optional `deployment.remote.user`, and certificate-based auth.
- If `deployment.scope` is `remote`, validate the remote user can execute the selected compose command: `docker compose version`, `podman compose version`, or `podman-compose --version`.
- If `deployment.scope` is `remote`, verify `deployment.remote.workdir` exists or can be created, and that the remote user can write to it.
- If `deployment.scope` is `remote`, do not require raw dataset files to exist on the SSH host. Verify dataset access where the declared loader will run. The SSH host normally receives compose assets and runtime support files only; raw data reaches Elasticsearch through `espipe`, Rally/esrally, or another declared indexing phase.
- If the scenario explicitly declares remote data generation, remote downloads, or a remote-local script phase, verify only those remote data prerequisites.
- Confirm the scenario's memory and disk expectations are realistic for the selected local or remote host.
- Confirm snapshot/searchable snapshot scenarios use a filesystem repository, not S3-compatible services, unless the scenario explicitly targets a non-local deployment.
- Confirm generated volume and repository paths are repo-local or clearly declared.

For `kubernetes`:

Kubernetes provider detection and confirmation:

- Run `kubectl cluster-info` to detect an existing cluster.
- If `deployment.kubernetes.provider` is declared, validate it. If `existing` and no cluster found, mark readiness `blocked`. If `k3s` and cluster already found, skip k3s install.
- If `deployment.kubernetes.provider` is omitted, ask the user:
  - **Cluster found:** "I found Kubernetes cluster `<context-name>` at `<endpoint>`. I'll create a `hypothetest` namespace and deploy ECK there. Is this the right cluster? If you'd rather use an isolated throwaway, I can install k3s instead."
  - **No cluster found:** "No Kubernetes cluster detected. I can install k3s — a lightweight single-node Kubernetes that runs as a system service. Clean removal with `k3s-uninstall.sh` when you're done. Proceed?"
- When provider is explicitly declared, skip the question but still echo what you're targeting before acting ("Using existing cluster `<context>` at `<endpoint>`" or "Installing k3s as declared").
- Record the resolved provider in readiness.toon as `kubernetes_provider: existing` or `kubernetes_provider: k3s`.

Kubernetes readiness checks (after provider is resolved):

- Verify `kubectl` can reach the cluster: `kubectl cluster-info`.
- Verify `helm` is available for ECK operator installation.
- Check whether the ECK operator is already installed in `elastic-system` namespace.
- If `deployment.kubernetes.install_operator: true` and operator is missing, note that `eck-up.sh` will install it.
- If `deployment.kubernetes.install_operator: false` and operator is missing, mark readiness `blocked`.
- Verify the declared namespace can be created or already exists.
- Check `vm.max_map_count` kernel setting; report as `verified` or `unverified` (drives initContainer generation decision in CRD manifests).
- Confirm the scenario's memory and storage expectations are realistic for the Kubernetes cluster's available resources.
- When `deployment.elasticsearch.security: false`, note that generated manifests will disable TLS and security — suitable for dev-grade local iteration, not production.

For `existing`:

- Echo the target before acting: "I'll run benchmarks against the Elasticsearch cluster at `<endpoint>`. This includes destructive resets (index deletion, cache clearing) in the `<namespace/prefix>` scope. Is this the right cluster?"
- Identify endpoint, auth method, TLS behavior, and whether destructive resets are allowed.
- Require an explicit namespace, index prefix, or disposable test cluster confirmation before destructive phases.
- Confirm the user understands that results are environment-dependent.

For `elastic-cloud`:

- Echo the target before acting: "I'll run benchmarks against Elastic Cloud deployment `<cloud_id or deployment_name>`. This includes destructive resets and may incur cost. Is this the right deployment?"
- Identify Cloud ID or endpoint, auth method, deployment ownership, and cleanup expectations.
- Confirm whether credentials are available through environment variables or a saved profile.
- Confirm cost and destructive reset boundaries before execution.
