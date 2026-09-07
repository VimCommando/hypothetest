# Workload plan

Read when selecting loaders, declaring fixtures, or compiling user-defined phases.

## Dataset loaders

Support both first-class loaders:

```yaml
dataset:
  loader: rally
  track: ./tracks/my-track
  challenge: append-no-conflicts-index-only
  params:
    bulk_size: 5000
```

```yaml
dataset:
  loader: espipe
  input: ./data/docs.ndjson
  target: benchmark-index
  options:
    batch_size: 5000
```

Use Rally when the workload is track/challenge oriented. Use espipe when the user wants to load a concrete NDJSON or CSV corpus.

Dataset locality is defined by the loader, not by the deployment SSH target. For remote compose, local input files, Rally tracks, and espipe inputs remain on the machine running the loader unless the dataset explicitly declares that the Operator must generate the data on the remote host. The SSH host does not receive a copy of raw corpus files as part of normal remote deployment setup.

Dataset fixtures in portable blueprints use one object shape:

- Use `path` for data included in the blueprint or expected to already exist.
- Use `generated_by` for data the Operator should generate during execution.
- Add checksum metadata when the blueprint includes local data.

## Benchmark phases

Represent benchmark work as user-defined phases, not as a fixed enum of operations.

```yaml
evaluation:
  repeats: 3
  order: randomized
  reset:
    - delete_indices
    - clear_caches
    - reload_dataset
    - verify_cluster_green
  phases:
    - name: load_data
      tool: espipe
      with:
        input: ./data/docs.ndjson
        target: benchmark-index
    - name: measured_search
      tool: rally
      with:
        track: ./tracks/search
        challenge: default
```

Allowed initial phase tools:

- `rally`
- `espipe`
- `elasticsearch_api`
- `shell`
- `python`

Use `shell` and `python` only when the hypothesis genuinely needs arbitrary local logic.

Every phase must have a `name` and `tool`. Put tool-specific options under `with`.
