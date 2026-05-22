# Hypothetest Repo Guidance

When working on Hypothetest:

- Treat benchmark scenarios as declarative experiment definitions, not fixed operations.
- Prefer `compose` as the first implementation target for fast local iteration.
- Support Docker and Podman where practical.
- Treat `hypothesis.md` as optional for the architect skill; when absent, build it interactively with the user.
- Keep operator behavior deterministic and artifact-oriented.
- Never let one variation inherit state from another unless the scenario explicitly opts in.
- Always preserve raw run artifacts before summarizing results.
