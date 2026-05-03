# Operator Evaluation Guide Template

1. Validate `hypothetest.yml`.
2. Resolve deployment target.
3. Resolve compose engine if target is `compose`.
4. Generate compose assets.
5. Start deployment.
6. Wait for cluster readiness.
7. For each variation and repeat:
   - reset state
   - load dataset
   - apply variation setup
   - execute evaluation phases
   - collect diagnostics with `esdiag` using the YAML-defined API list for each collection point
   - optionally process the diagnostic bundle to a results cluster
   - archive artifacts
8. Stop or preserve deployment according to scenario cleanup policy.
9. Write evaluation manifest.
