# docker

Container engine and compose orchestrator for deployment targets.

## When loaded

When `deployment.engine` resolves to `docker`.

## Install

### macOS
```bash
brew install --cask docker
```

### Linux (Debian/Ubuntu)
```bash
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
```

### Linux (RHEL/Fedora)
```bash
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
```

## Version check
```bash
docker --version
docker compose version
```

## Readiness preflight

Verify the Docker daemon is running and compose is functional:
```bash
docker info >/dev/null 2>&1
docker compose version >/dev/null 2>&1
```

For remote scope, verify compose on the remote host:
```bash
ssh <ssh_config_host> docker compose version
```

## URL

- https://docs.docker.com/
- https://github.com/docker/compose
