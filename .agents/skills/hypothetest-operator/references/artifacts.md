# Evaluation Artifacts

The authoritative evaluation artifact contract is
the Operator skill's bundled `schemas/evaluation.schema.yaml`. Operator output
must include an `evaluation.yml` file that validates against that schema.

`evaluation.yml` is the schema-valid index for the evaluation directory. It
points to the preserved evidence, diagnostics, phase output, generated assets,
normalized measurements, comparisons, charts, summary, and report.

The recommended root remains `evaluations/<hypothesis-name>/<timestamp>/`, but
the required structure is whatever `evaluation.yml` indexes. Do not duplicate a
second artifact contract here.

`manifest.toon` is the compact runtime manifest. It complements
`evaluation.yml`; it is not the schema-valid artifact index.

Hypothetest structured evaluation data is stored as TOON (`.toon`). Raw `esdiag` diagnostics remain bundled `.zip` artifacts. Configurations remain YAML/YML. All analysis must be reproducible from this directory.
