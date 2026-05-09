# podman

Rootless container engine and compose orchestrator for deployment targets.

## When loaded

When `deployment.engine` resolves to `podman`.

## Install

### macOS
```bash
brew install podman podman-compose
```

### Linux (Debian/Ubuntu)
```bash
sudo apt-get install -y podman podman-compose
```

### Linux (RHEL/Fedora)
```bash
sudo dnf install -y podman podman-compose
```

## Version check
```bash
podman --version
podman compose version 2>/dev/null || podman-compose --version
```

## Readiness preflight

Podman supports two compose variants:
- `podman compose` — built-in subcommand (Podman 4.x+)
- `podman-compose` — standalone Python wrapper

Verify Podman can run containers and at least one compose variant is functional:
```bash
podman info >/dev/null 2>&1
podman compose version >/dev/null 2>&1 || podman-compose --version >/dev/null 2>&1
```

For remote scope, verify compose on the remote host:
```bash
ssh <ssh_config_host> "podman compose version 2>/dev/null || podman-compose --version"
```

## URL

- https://podman.io/
- https://github.com/containers/podman
