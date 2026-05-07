# Compose Templates

Pattern catalog for generating compose infrastructure assets. The Coordinator
reads `readiness.toon` and the blueprint's deployment block, then adapts
these patterns to produce `generated/compose/` assets and lifecycle scripts.

This is a pattern catalog: complete, annotated examples the Coordinator
adapts per experiment. Not parameterized `{{variable}}` templates.

## Input contract

Two inputs drive compose generation decisions:

**readiness.toon** — what's available on the target platform:
```toon
deployment_target: compose
compose_engine: podman
scope: remote
ssh_host: ironhide.local
remote_workdir: /tmp/hypothetest/evaluations
```

**deployment block** from hypothetest.yml — what the blueprint declares:
```yaml
deployment:
  target: compose
  scope: local
  engine: auto
  elasticsearch:
    version: 8.18.0
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

Generation rules:
- All versions come from the blueprint declaration — never hardcode
- Generate compose services only for declared components (skip Kibana when `services.kibana: false`)
- Engine comes from readiness resolution, not guesswork
- When `security: false`, disable TLS and xpack security in both compose.yml and elasticsearch.yml
- When `repositories` are declared, generate volume mounts for filesystem paths
- Remote scope stages compose files via SCP, executes via SSH

## Generated output layout

```
generated/compose/
  compose.yml              # Compose V2 service definition
  .env                     # Version, heap, memory variables
  elasticsearch.yml        # Custom elasticsearch.yml (bind-mounted)
generated/scripts/
  compose-up.sh            # Start cluster (local or remote)
  compose-down.sh          # Stop cluster and remove volumes
```

The Coordinator generates lifecycle scripts alongside compose assets.
The Operator consumes both through evaluation.sh.

## Engine handling

### Resolution order (engine: auto)

```bash
# 1. Prefer docker compose (V2 plugin)
docker compose version

# 2. Else podman compose (V2 plugin)
podman compose version

# 3. Else podman-compose (standalone)
podman-compose --version

# 4. Else fail
```

When `engine: docker` or `engine: podman` is explicit, skip detection and
use the declared engine directly. Fail if it's unavailable.

### Engine variable in scripts

```bash
COMPOSE_ENGINE="${HYPOTHETEST_COMPOSE_ENGINE:-docker compose}"
```

The Coordinator sets this in generated scripts based on readiness resolution:

| Resolved engine | COMPOSE_ENGINE value |
|---|---|
| Docker Compose V2 | `docker compose` |
| Podman Compose plugin | `podman compose` |
| podman-compose standalone | `podman-compose` |

### Network differences

Docker and Podman handle container networking differently:

- **Docker**: containers on the same compose network resolve by service name
- **Podman (rootless)**: uses slirp4netns; port-mapped services accessible via `localhost` from host but not cross-container by default without a pod or explicit network

For Hypothetest, this rarely matters — benchmarks access Elasticsearch via
the mapped host port (9200), not cross-container. The compose.yml patterns
work identically for both engines.

## Compose file patterns

### Single-node development (default)

The baseline pattern. Security disabled, single node, named volume for data.

```yaml
services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:${ES_VERSION}
    container_name: hypothetest-es
    environment:
      - node.name=hypothetest-es
      - cluster.name=hypothetest
      - discovery.type=single-node
      - xpack.security.enabled=false
      - xpack.security.http.ssl.enabled=false
      - xpack.security.transport.ssl.enabled=false
      - ES_JAVA_OPTS=-Xms${ES_HEAP} -Xmx${ES_HEAP}
      - bootstrap.memory_lock=true
    ulimits:
      memlock:
        soft: -1
        hard: -1
      nofile:
        soft: 65536
        hard: 65536
    mem_limit: ${ES_MEMORY}
    ports:
      - "9200:9200"
    volumes:
      - esdata:/usr/share/elasticsearch/data
      - ./elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml:ro,z
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:9200/_cluster/health | grep -qE '\"status\":\"(green|yellow)\"'"]
      interval: 10s
      timeout: 10s
      retries: 12
      start_period: 30s

volumes:
  esdata:
    driver: local
```

Adaptation points:
- `${ES_VERSION}` from `deployment.elasticsearch.version`
- `${ES_HEAP}` from `deployment.elasticsearch.heap`
- `${ES_MEMORY}` from `deployment.elasticsearch.memory`
- `container_name` and `node.name` use `hypothetest-es` by default
- `discovery.type: single-node` when `deployment.elasticsearch.nodes: 1`

### Single-node with security enabled

When `deployment.elasticsearch.security: true`. Enables TLS and basic auth.

```yaml
services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:${ES_VERSION}
    container_name: hypothetest-es
    environment:
      - node.name=hypothetest-es
      - cluster.name=hypothetest
      - discovery.type=single-node
      - xpack.security.enabled=true
      - xpack.security.http.ssl.enabled=true
      - xpack.security.http.ssl.certificate=certs/http.p12
      - xpack.security.transport.ssl.enabled=true
      - xpack.security.transport.ssl.certificate=certs/transport.p12
      - ELASTIC_PASSWORD=${ES_PASSWORD}
      - ES_JAVA_OPTS=-Xms${ES_HEAP} -Xmx${ES_HEAP}
      - bootstrap.memory_lock=true
    ulimits:
      memlock:
        soft: -1
        hard: -1
      nofile:
        soft: 65536
        hard: 65536
    mem_limit: ${ES_MEMORY}
    ports:
      - "9200:9200"
    volumes:
      - esdata:/usr/share/elasticsearch/data
      - ./elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml:ro,z
    healthcheck:
      test: ["CMD-SHELL", "curl -sf -k -u elastic:${ES_PASSWORD} https://localhost:9200/_cluster/health | grep -qE '\"status\":\"(green|yellow)\"'"]
      interval: 10s
      timeout: 10s
      retries: 12
      start_period: 30s

volumes:
  esdata:
    driver: local
```

Additional `.env` entries when security is enabled:
```
ES_PASSWORD=changeme
```

The Coordinator generates a random password and writes it to `.env`.
The compose-up.sh script exports `ELASTICSEARCH_URL=https://localhost:9200`
and `ELASTICSEARCH_PASSWORD` for downstream tools.

### Multi-node cluster

When `deployment.elasticsearch.nodes > 1`. Each node is a separate service
with its own named volume.

```yaml
services:
  es01:
    image: docker.elastic.co/elasticsearch/elasticsearch:${ES_VERSION}
    container_name: hypothetest-es01
    environment:
      - node.name=hypothetest-es01
      - cluster.name=hypothetest
      - discovery.seed_hosts=hypothetest-es02,hypothetest-es03
      - cluster.initial_master_nodes=hypothetest-es01,hypothetest-es02,hypothetest-es03
      - xpack.security.enabled=false
      - xpack.security.http.ssl.enabled=false
      - xpack.security.transport.ssl.enabled=false
      - ES_JAVA_OPTS=-Xms${ES_HEAP} -Xmx${ES_HEAP}
      - bootstrap.memory_lock=true
    ulimits:
      memlock:
        soft: -1
        hard: -1
      nofile:
        soft: 65536
        hard: 65536
    mem_limit: ${ES_MEMORY}
    ports:
      - "9200:9200"
    volumes:
      - esdata01:/usr/share/elasticsearch/data
      - ./elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml:ro,z
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:9200/_cluster/health | grep -qE '\"status\":\"(green|yellow)\"'"]
      interval: 10s
      timeout: 10s
      retries: 12
      start_period: 30s

  es02:
    image: docker.elastic.co/elasticsearch/elasticsearch:${ES_VERSION}
    container_name: hypothetest-es02
    environment:
      - node.name=hypothetest-es02
      - cluster.name=hypothetest
      - discovery.seed_hosts=hypothetest-es01,hypothetest-es03
      - cluster.initial_master_nodes=hypothetest-es01,hypothetest-es02,hypothetest-es03
      - xpack.security.enabled=false
      - xpack.security.http.ssl.enabled=false
      - xpack.security.transport.ssl.enabled=false
      - ES_JAVA_OPTS=-Xms${ES_HEAP} -Xmx${ES_HEAP}
      - bootstrap.memory_lock=true
    ulimits:
      memlock:
        soft: -1
        hard: -1
      nofile:
        soft: 65536
        hard: 65536
    mem_limit: ${ES_MEMORY}
    volumes:
      - esdata02:/usr/share/elasticsearch/data
      - ./elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml:ro,z

  es03:
    image: docker.elastic.co/elasticsearch/elasticsearch:${ES_VERSION}
    container_name: hypothetest-es03
    environment:
      - node.name=hypothetest-es03
      - cluster.name=hypothetest
      - discovery.seed_hosts=hypothetest-es01,hypothetest-es02
      - cluster.initial_master_nodes=hypothetest-es01,hypothetest-es02,hypothetest-es03
      - xpack.security.enabled=false
      - xpack.security.http.ssl.enabled=false
      - xpack.security.transport.ssl.enabled=false
      - ES_JAVA_OPTS=-Xms${ES_HEAP} -Xmx${ES_HEAP}
      - bootstrap.memory_lock=true
    ulimits:
      memlock:
        soft: -1
        hard: -1
      nofile:
        soft: 65536
        hard: 65536
    mem_limit: ${ES_MEMORY}
    volumes:
      - esdata03:/usr/share/elasticsearch/data
      - ./elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml:ro,z

volumes:
  esdata01:
    driver: local
  esdata02:
    driver: local
  esdata03:
    driver: local
```

Adaptation points:
- Number of `esNN` services matches `deployment.elasticsearch.nodes`
- Only the first node maps port 9200 (healthcheck runs against it)
- `discovery.seed_hosts` lists all other node container names
- `cluster.initial_master_nodes` lists all node names
- Each node gets its own named volume

### With Kibana

When `deployment.services.kibana: true`. Add a Kibana service connected
to Elasticsearch.

```yaml
  kibana:
    image: docker.elastic.co/kibana/kibana:${ES_VERSION}
    container_name: hypothetest-kibana
    environment:
      - ELASTICSEARCH_HOSTS=http://hypothetest-es:9200
      - xpack.security.enabled=false
    ports:
      - "5601:5601"
    depends_on:
      elasticsearch:
        condition: service_healthy
```

When security is enabled:
```yaml
    environment:
      - ELASTICSEARCH_HOSTS=https://hypothetest-es:9200
      - ELASTICSEARCH_USERNAME=kibana_system
      - ELASTICSEARCH_PASSWORD=${ES_PASSWORD}
      - xpack.security.enabled=true
```

Kibana version always matches the Elasticsearch version from the blueprint.

### With filesystem repository

For snapshot, searchable snapshot, frozen-like, or repository benchmarks.
Mounts a host directory into the container as a filesystem repo path.

```yaml
services:
  elasticsearch:
    # ... (base pattern plus:)
    volumes:
      - esdata:/usr/share/elasticsearch/data
      - ./elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml:ro,z
      - snapshots:/usr/share/elasticsearch/snapshots/bench-repo

volumes:
  esdata:
    driver: local
  snapshots:
    driver: local
```

The corresponding `elasticsearch.yml` must declare the repo path:
```yaml
path.repo: ["/usr/share/elasticsearch/snapshots/bench-repo"]
```

Multiple repositories use multiple volume mounts:
```yaml
    volumes:
      - snapshots-a:/usr/share/elasticsearch/snapshots/repo-a
      - snapshots-b:/usr/share/elasticsearch/snapshots/repo-b
```

With `path.repo` listing all paths:
```yaml
path.repo:
  - /usr/share/elasticsearch/snapshots/repo-a
  - /usr/share/elasticsearch/snapshots/repo-b
```

## Environment file (.env) pattern

The `.env` file parameterizes the compose.yml using `${VAR}` substitution.
The Coordinator populates it from the blueprint's deployment block.

```bash
# Elasticsearch version — must match hypothetest.yml deployment.elasticsearch.version
ES_VERSION=8.18.0

# JVM heap — must match hypothetest.yml deployment.elasticsearch.heap
ES_HEAP=2g

# Container memory limit — must match hypothetest.yml deployment.elasticsearch.memory
ES_MEMORY=4g
```

Additional entries by condition:

| Condition | Entry |
|---|---|
| `security: true` | `ES_PASSWORD=<generated>` |
| `nodes > 1` | (no extra — node count is structural, not env) |

## Custom elasticsearch.yml

The Coordinator generates `generated/compose/elasticsearch.yml` as a
bind-mounted configuration file. It always includes:

```yaml
cluster.name: hypothetest
node.name: hypothetest-es

# Single-node (or multi-node discovery settings)
discovery.type: single-node

# Security (matches compose.yml environment block)
xpack.security.enabled: false
xpack.security.http.ssl.enabled: false
xpack.security.transport.ssl.enabled: false

# Network
network.host: 0.0.0.0
http.port: 9200
```

Additional entries by condition:

| Condition | Entry |
|---|---|
| `repositories` declared | `path.repo: ["/usr/share/elasticsearch/snapshots/<name>"]` |
| `nodes > 1` | Remove `discovery.type: single-node`, add seed hosts |
| `security: true` | Remove security disabled lines |

The `:ro,z` suffix on the bind mount makes it read-only with SELinux
relabeling (works on both Docker and Podman).

## Scope: local vs remote

### Local compose

Direct execution on the operator's machine:

```bash
${COMPOSE_ENGINE} -f generated/compose/compose.yml up -d
```

Health check hits `http://localhost:9200` directly.

### Remote compose

SSH-based execution. The Coordinator generates compose-up.sh with:

1. Create remote workdir
2. SCP compose assets to remote host
3. Execute compose up via SSH
4. Health check hits `http://<ssh_host>:9200`

```bash
SSH_HOST="ironhide.local"
REMOTE_WORKDIR="/tmp/hypothetest/evaluations"
COMPOSE_DIR="generated/compose"

# Stage files
ssh "${SSH_HOST}" mkdir -p "${REMOTE_WORKDIR}/${COMPOSE_DIR}"
scp -q \
  "${COMPOSE_DIR}/compose.yml" \
  "${COMPOSE_DIR}/.env" \
  "${COMPOSE_DIR}/elasticsearch.yml" \
  "${SSH_HOST}:${REMOTE_WORKDIR}/${COMPOSE_DIR}/"

# Start
ssh "${SSH_HOST}" "cd ${REMOTE_WORKDIR} && ${COMPOSE_ENGINE} -f ${COMPOSE_DIR}/compose.yml up -d"
```

Remote teardown follows the same SSH pattern:
```bash
ssh "${SSH_HOST}" "cd ${REMOTE_WORKDIR} && ${COMPOSE_ENGINE} -f ${COMPOSE_DIR}/compose.yml down -v"
```

Key rules for remote:
- Only compose assets are staged to the remote host (compose.yml, .env, elasticsearch.yml)
- Raw dataset files are NOT copied — loaders connect to ES via the network
- SSH auth uses the user's `.ssh/config` with certificate-based auth
- The `deployment.remote.workdir` is the working directory on the remote host

## Health check and readiness

### In-container healthcheck (compose.yml)

The compose healthcheck ensures the container reports healthy to compose:

```yaml
healthcheck:
  test: ["CMD-SHELL", "curl -sf http://localhost:9200/_cluster/health | grep -qE '\"status\":\"(green|yellow)\"'"]
  interval: 10s
  timeout: 10s
  retries: 12
  start_period: 30s
```

### Script-level health wait (compose-up.sh)

The lifecycle script waits for ES to respond from the host's perspective:

```bash
HEALTH_TIMEOUT=120
HEALTH_INTERVAL=5
elapsed=0

while (( elapsed < HEALTH_TIMEOUT )); do
  if curl -sf "${ES_URL}/_cluster/health" | grep -qE '"status":"(green|yellow)"'; then
    echo "[healthy] elapsed=${elapsed}s url=${ES_URL}"
    exit 0
  fi
  sleep "${HEALTH_INTERVAL}"
  elapsed=$(( elapsed + HEALTH_INTERVAL ))
done

echo "[failed] reason=health_timeout elapsed=${elapsed}s"
exit 1
```

For local: `ES_URL=http://localhost:9200`
For remote: `ES_URL=http://<ssh_host>:9200`
For security: `ES_URL=https://localhost:9200` with `-k -u elastic:${ES_PASSWORD}`

## Volume and data patterns

### Named volumes (default)

Named volumes persist data across container restarts. Used for ES data:

```yaml
volumes:
  esdata:
    driver: local
```

### Cleanup

`compose-down.sh` uses `-v` to remove named volumes:

```bash
${COMPOSE_ENGINE} -f ${COMPOSE_DIR}/compose.yml down -v
```

This ensures each evaluation starts clean. Without `-v`, data persists
and variation isolation is compromised.

### Snapshot repository volumes

For filesystem repositories, use additional named volumes mounted at
the declared `path.repo` location inside the container. These are also
cleaned by `down -v`.

## Port mapping

| Service | Default mapping | Notes |
|---|---|---|
| Elasticsearch | `9200:9200` | Always mapped on first (or only) node |
| Kibana | `5601:5601` | Only when `services.kibana: true` |

For multi-node, only the first node (`es01`) maps port 9200. All nodes
communicate on the internal compose network without port mapping.

## Compose-specific environment variables

Variables the Coordinator uses in generated scripts:

| Variable | Default | Purpose |
|---|---|---|
| `HYPOTHETEST_COMPOSE_ENGINE` | `docker compose` | Override resolved engine |
| `HYPOTHETEST_DRY_RUN` | `false` | Skip actual compose commands |
| `ES_URL` | `http://localhost:9200` | Elasticsearch endpoint for health checks |

Variables in `.env` (compose substitution):

| Variable | Source | Purpose |
|---|---|---|
| `ES_VERSION` | `deployment.elasticsearch.version` | Image tag |
| `ES_HEAP` | `deployment.elasticsearch.heap` | JVM heap size |
| `ES_MEMORY` | `deployment.elasticsearch.memory` | Container memory limit |
| `ES_PASSWORD` | Generated | Elastic user password (security only) |

## Readiness signals driving compose generation

| Readiness signal | Generation decision |
|---|---|
| `compose_engine: docker` | Use `docker compose` in scripts |
| `compose_engine: podman` | Use `podman compose` or `podman-compose` |
| `scope: local` | Direct execution, localhost health checks |
| `scope: remote` | SSH execution, remote host health checks |
| `ssh_host: <name>` | SCP target and SSH command host |
| `remote_workdir: <path>` | Working directory on remote host |
| `security: false` | Disable TLS, use HTTP health checks |
| `security: true` | Enable TLS, use HTTPS health checks with creds |
| `repositories: <list>` | Generate volume mounts and path.repo |
| `kibana: true` | Generate Kibana service in compose.yml |

## Decision table: blueprint → compose output

| Blueprint field | Compose output |
|---|---|
| `deployment.elasticsearch.version` | `.env` ES_VERSION, image tag |
| `deployment.elasticsearch.nodes` | Number of service entries (1 = single-node, N = multi-node) |
| `deployment.elasticsearch.heap` | `.env` ES_HEAP, ES_JAVA_OPTS |
| `deployment.elasticsearch.memory` | `.env` ES_MEMORY, mem_limit |
| `deployment.elasticsearch.security` | Security env vars, healthcheck scheme, .env password |
| `deployment.services.kibana` | Kibana service block present/absent |
| `deployment.repositories.*` | Volume mounts + path.repo in elasticsearch.yml |
| `deployment.scope` | Local vs SSH execution in lifecycle scripts |
| `deployment.engine` | COMPOSE_ENGINE value in scripts |
| `deployment.remote.host` | SSH_HOST in compose-up.sh |
| `deployment.remote.workdir` | REMOTE_WORKDIR in compose-up.sh |
