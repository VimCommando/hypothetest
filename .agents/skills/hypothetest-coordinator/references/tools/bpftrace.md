# bpftrace

eBPF tracing tool for off-CPU analysis and kernel-level instrumentation.

## When loaded

When `off_cpu` method is prescribed in `diagnostics.during`.

## Install

### Linux (Debian/Ubuntu)
```bash
sudo apt-get install -y bpftrace
```

### Linux (RHEL/Fedora)
```bash
sudo dnf install -y bpftrace
```

## Version check
```bash
bpftrace --version
```

## Readiness preflight

Verify bpftrace has sufficient privileges (CAP_BPF or root):
```bash
sudo bpftrace -e 'BEGIN { exit(); }' 2>/dev/null
```

## URL
https://bpftrace.org/
