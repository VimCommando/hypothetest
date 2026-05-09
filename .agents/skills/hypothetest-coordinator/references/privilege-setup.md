# Privilege Setup Options

When `sudo -n` fails for commands declared by the evaluation, present
these options to the user. Each is progressively broader in scope.
The user chooses which approach fits their environment.

Do not auto-apply any of these. Generate the specific content based on
the Architect's declared privileged commands, present it, and let the
user decide.

## Option 1: Sudoers drop-in file (narrowest scope)

Generate a drop-in file scoped to exactly the commands the evaluation
needs. Example for an evaluation that drops caches and adjusts
`merge_factor`:

```
# /etc/sudoers.d/hypothetest-eval
# Scoped to this evaluation's declared privileged commands.
# Review and install: sudo visudo -f /etc/sudoers.d/hypothetest-eval
# Remove after evaluation: sudo rm /etc/sudoers.d/hypothetest-eval

<username> ALL=(root) NOPASSWD: /bin/sh -c echo 3 > /proc/sys/vm/drop_caches
<username> ALL=(root) NOPASSWD: /usr/sbin/sysctl -w vm.*
```

Replace `<username>` with the user running the evaluation. Scope each
entry to the exact command and arguments when possible.

Present the generated file content and suggest:
```bash
# Review the file, then install:
sudo install -m 0440 /dev/stdin /etc/sudoers.d/hypothetest-eval <<'EOF'
<generated content>
EOF

# Verify:
sudo -n sh -c 'echo 3 > /proc/sys/vm/drop_caches'

# Remove after evaluation:
sudo rm /etc/sudoers.d/hypothetest-eval
```

## Option 2: Dedicated runner user (moderate scope)

A user created for evaluation work with group memberships for container
engines and scoped sudo access. Useful when running multiple evaluations
or when the primary user should not have direct sudo.

```bash
# Create user with docker/podman group access
sudo useradd -m -s /bin/bash hypothetest-runner
sudo usermod -aG docker hypothetest-runner  # or: podman group

# Install scoped sudoers (same as Option 1, for hypothetest-runner)
sudo visudo -f /etc/sudoers.d/hypothetest-runner

# Run evaluation as the runner
sudo -u hypothetest-runner bash -c 'cd /path/to/blueprint && ./generated/scripts/evaluation.sh run'

# Optional: remove after evaluation
sudo userdel -r hypothetest-runner
sudo rm /etc/sudoers.d/hypothetest-runner
```

Adapt group memberships to the deployment engine (`docker`, `podman`).
The runner user needs read access to the blueprint directory and write
access to the evaluation output directory.

## Option 3: Linux capabilities (narrowest possible, no sudo)

For specific privileged operations, a capability-wrapped binary avoids
sudo entirely. This is the most restrictive option but requires
per-command setup.

Common evaluation operations and their capabilities:

| Operation | Capability | Setup |
|---|---|---|
| Drop page cache | `CAP_SYS_ADMIN` | Wrapper script with `setcap` |
| Adjust sysctl | `CAP_SYS_ADMIN` | Wrapper script with `setcap` |
| perf record | `CAP_PERFMON` | `setcap cap_perfmon+ep $(which perf)` |
| bpftrace | `CAP_BPF`, `CAP_PERFMON` | `setcap cap_bpf,cap_perfmon+ep $(which bpftrace)` |

Example wrapper for drop_caches:
```bash
#!/bin/bash
# /usr/local/bin/drop-caches
# After creating: sudo setcap cap_sys_admin+ep /usr/local/bin/drop-caches
echo 3 > /proc/sys/vm/drop_caches
```

Capabilities are persistent across reboots. Remove with:
```bash
sudo setcap -r /usr/local/bin/drop-caches
```

## Presenting to the user

When `sudo -n` fails during readiness, present all applicable options:

1. State which commands failed and why they are needed.
2. Show Option 1 with the exact generated sudoers content.
3. Mention Options 2 and 3 as alternatives if the user wants
   narrower access or a dedicated user.
4. Let the user choose. Record their choice in readiness.toon.
5. After they apply their chosen setup, re-verify with `sudo -n`.
