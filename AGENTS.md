# Hypothetest Repo Guidance

When working on Hypothetest:

- Treat benchmark scenarios as declarative experiment definitions, not fixed operations.
- Prefer `compose` as the first implementation target for fast local iteration.
- Support Docker and Podman where practical.
- Treat `scenario.md` as optional for the architect skill; when absent, build it interactively with the user.
- Keep operator behavior deterministic and artifact-oriented.
- Never let one variation inherit state from another unless the scenario explicitly opts in.
- For remote compose, use the container engine's published service port as the
  benchmark data plane. SSH is control-plane access only. Treat direct
  DNS/network/tool connectivity failures as readiness blockers; do not create
  SSH tunnels, loopback forwards, or proxy workarounds.
- Run dataset loaders and diagnostic clients on the local Operator host for
  remote-compose evaluations unless the scenario explicitly requires another
  locality. They must use the same directly published remote service endpoint.
- Force-merge experiments must prove merge quiescence before load, after load
  and before the measured force merge, and after force merge before another
  variation or repeat starts. Require zero active node merges, zero active or
  queued merge-thread-pool work, and zero force-merge tasks across consecutive
  polls, and preserve the poll evidence.
- Store raw run measurements as a wide TOON table: one row per
  variation/repeat and one unit-qualified column per metric. Put invariant
  evaluation identity, metric sources, and metric phases in a metadata block,
  not in every row. Use `null` plus a run-level status for missing values.
- Always preserve raw run artifacts before summarizing results.
