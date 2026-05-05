# Operator Evaluation Guide Template

1. Validate `hypothetest.yml`.
2. Resolve deployment target.
3. Resolve compose engine if target is `compose`.
4. Generate compose assets.
5. Start deployment.
6. Wait for cluster readiness.
7. For each variation and repeat:
   - record variation start time
   - reset state
   - load dataset through the declared indexing/workload tool
   - apply variation setup
   - execute evaluation phases (via sampling script when `diagnostics.during` is declared)
   - collect diagnostics with `esdiag` using the YAML-defined API list for each collection point
   - optionally process the diagnostic bundle to a results cluster
   - archive artifacts
   - record variation completed time and runtime
8. Stop or preserve deployment according to scenario cleanup policy.
9. Write evaluation manifest with total runtime and per-variation runtime.

For remote compose, SSH manages the deployment host only. Do not stage raw
dataset files to the SSH host by default. `espipe`, Rally/esrally, or another declared
loader sends data to the Elasticsearch endpoint exposed by the deployment from
the loader's configured execution location.
