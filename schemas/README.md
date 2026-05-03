# Schemas

These repo-root schemas are development mirrors. Distributable skills also carry
the schema they own so sandboxed environments do not depend on repo-root file
access.

- `hypothetest.schema.yaml`: Hypothetest plan contract for `hypothetest.yml`.
  Owned by the Coordinator skill.
- `blueprint.schema.yaml`: portable blueprint manifest contract for
  `blueprint.yml`. Owned by the Architect skill.
- `evaluation.schema.yaml`: completed or partial evaluation artifact index
  contract for `evaluation.yml`. Owned by the Operator skill.
