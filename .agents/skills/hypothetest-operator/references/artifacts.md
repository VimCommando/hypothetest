# Run Artifact Layout

```text
runs/<scenario>/<timestamp>/
  manifest.toon
  hypothesis.md
  hypothetest.yml
  generated/
  variations/
    <variation>/
      repeat-001/
        phase-001-load_data/
          command.txt
          stdout.log
          stderr.log
          started_at.txt
          completed_at.txt
          metrics-before.toon
          metrics-after.toon
        raw/
          esdiag/
            <collection-point>.zip
        metrics/
```

Hypothetest structured run data is stored as TOON (`.toon`). Raw `esdiag` diagnostics remain bundled `.zip` artifacts. Configurations remain YAML/YML. All analysis must be reproducible from this directory.
