# ssh

SSH client for remote compose scope — certificate-based access to
deployment hosts.

## When loaded

When `deployment.scope: remote` in the blueprint.

## Install

Included with macOS and most Linux distributions.

## Version check
```bash
ssh -V
```

## Readiness preflight

Verify the SSH config host resolves and certificate auth succeeds:
```bash
ssh -o BatchMode=yes -o ConnectTimeout=5 <ssh_config_host> true
```

Verify compose engine is available on the remote host:
```bash
ssh <ssh_config_host> "docker compose version 2>/dev/null || podman-compose --version"
```

Verify the remote workdir is writable:
```bash
ssh <ssh_config_host> "mkdir -p /tmp/hypothetest/evaluations && test -w /tmp/hypothetest/evaluations"
```
