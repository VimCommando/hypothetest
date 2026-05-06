# perf

Linux performance counter profiler for on-CPU flame graph collection.

## When loaded

When `on_cpu` method is prescribed in `diagnostics.during`.

## Install

### Linux (Debian/Ubuntu)
```bash
sudo apt-get install -y linux-tools-common linux-tools-$(uname -r)
```

### Linux (RHEL/Fedora)
```bash
sudo dnf install -y perf
```

## Version check
```bash
perf --version
```

## Readiness preflight

Verify perf has sufficient privileges (CAP_PERFMON or root):
```bash
perf stat -e cycles true 2>/dev/null
```

## References

- [Brendan Gregg's perf examples](https://www.brendangregg.com/perf.html) — annotated examples for CPU profiling, flame graphs, and event tracing
- [perf wiki tutorial](https://perf.wiki.kernel.org/index.php/Tutorial)

## URL

- https://perf.wiki.kernel.org/
- https://github.com/torvalds/linux/tree/master/tools/perf
