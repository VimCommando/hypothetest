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

## References

- [bpftrace tools/](https://github.com/bpftrace/bpftrace/tree/master/tools) — ready-to-use scripts for CPU, I/O, memory, filesystem, and network tracing
- [bpftrace one-liners tutorial](https://github.com/bpftrace/bpftrace/blob/master/docs/tutorial_one_liners.md)

## URL

- https://bpftrace.org/
- https://github.com/bpftrace/bpftrace
