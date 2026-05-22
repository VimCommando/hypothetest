# esdiag Operations

Operational reference for running `esdiag` during Hypothetest evaluations.
Load this reference when the blueprint uses `measure.diagnostics.tool: esdiag`.

## Named hosts

`esdiag collect` requires a named host registered in `~/.esdiag/hosts.yml`.
It does not accept a raw URL as a positional argument. The Coordinator
registers the host during readiness with:

```bash
esdiag host add <name> elasticsearch <url>
```

The registered host name is recorded in readiness.toon and in the
generated `.env` file. Use this name when running `esdiag collect`.

## Collection syntax

```bash
esdiag collect [OPTIONS] <HOST> <OUTPUT_DIR>
```

- `<HOST>` is the registered host name, not a URL.
- `<OUTPUT_DIR>` is an existing directory for the diagnostic bundle.
- `--type <TYPE>` selects the diagnostic scope: `minimal`, `light`,
  `standard` (default), or `support`.
- `--include <INCLUDE>` is a comma-separated list of APIs to include.
  The identifiers accepted by `--include` may not match raw ES API
  paths — verify the available identifiers with `esdiag collect --help`.
- `--exclude <EXCLUDE>` excludes specific APIs from the collection.

## Output format

`esdiag collect` writes a `.zip` bundle to the output directory. To
access individual API responses, unzip the bundle first:

```bash
unzip -q -o "${zip_file}" -d "${outdir}"
```

Filenames inside the zip do not have leading underscores:
`nodes_stats.json`, not `_nodes_stats.json`.

## Default collection coverage

The default (`--type standard`) collection includes:

- `nodes_stats` — segment counts, merge stats, GC counters, thread pools
- `indices_stats` — per-index store size, document counts, indexing stats
- `cluster_health` — cluster status, shard counts

This covers most measurement plan requirements. Verify coverage against
the plan's `measure.diagnostics.at.required_apis` list before using
`--include` to add extras.

## Diagnostics API list

The `required_apis` list in `measure.diagnostics.at` declares which API
responses the measurement plan requires. After collection, verify each
listed API has a corresponding file in the unzipped bundle. If a
required API is missing from the default collection, use `--include` to
add it — but note that `--include` may use esdiag's own named
identifiers rather than raw ES API paths.
