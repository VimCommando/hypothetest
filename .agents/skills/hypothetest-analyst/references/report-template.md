# Report Template

```markdown
# Result

One-paragraph answer to the scenario question.

# What was compared

| Variation | Key settings | Repeats | Status |
|---|---|---:|---|

# Constants and variables

Experiment intent, required and best-effort constants, deliberately varied factors, and observed mismatches.

# Evaluation quality

Deployment target, result quality, failures, missing metrics, isolation notes.

# Runtime

Total evaluation runtime and per-variation runtime.

| Variation | Repeat | Runtime | Status |
|---|---:|---:|---|

# Primary metrics

| Metric | Baseline | Candidate | Delta | Delta % | Confidence |
|---|---:|---:|---:|---:|---|

# Interpretation

Explain likely causes of observed deltas.

# Caveats

List limitations.

# Reproduction

Point to scenario, canonical YAML plan, TOON evaluation manifest, and commands.

# Appendix

Secondary metrics and raw artifact references.
```
