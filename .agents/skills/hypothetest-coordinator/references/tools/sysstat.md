# sysstat

System performance monitoring suite (iostat, mpstat, pidstat, vmstat).

## When loaded

When `standard` or `comprehensive` profile is prescribed on Linux —
provides host-level CPU, disk I/O, and memory signals that supplement
the ES API USE method.

## Install

### Linux (Debian/Ubuntu)
```bash
sudo apt-get install -y sysstat
```

### Linux (RHEL/Fedora)
```bash
sudo dnf install -y sysstat
```

## Version check
```bash
iostat -V
```

## Readiness preflight

Verify iostat and mpstat are functional:
```bash
iostat -x 1 1 >/dev/null 2>&1
mpstat 1 1 >/dev/null 2>&1
```

## URL
https://sysstat.github.io/
