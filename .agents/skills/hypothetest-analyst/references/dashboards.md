# Dashboard publishing

Read after report artifacts are complete when dashboard work is requested or available within the authorized analysis workflow. Prepare local definitions first; apply connectivity gates only to live operations.

## Kibana dashboard workflow

Use the `kibana-dashboards` skill after report compilation, in this order:

1. Read the `kibana-dashboards` skill's SKILL.md (if available) before creating dashboard JSON.
2. Identify which collected evidence is already queryable in Elasticsearch:
   - Reuse `esdiag` results data streams when diagnostics were processed into a results cluster.
   - Reuse any Rally, espipe, phase-output, or custom measurement indices already declared in `evaluation.yml` or `manifest.toon`.
3. For Hypothetest measurements that are only local artifacts and not already indexed, create documents for the shared custom measurement data stream before dashboard creation.
4. Write generated dashboard definitions and ingestion assets under `dashboards/`.
5. Test Kibana connectivity with the dashboard skill's required command before creating or updating dashboards.
6. If the Kibana connection test fails, preserve the dashboard JSON and ingestion assets, explain the required environment variables in the report appendix or final response, and stop before attempting dashboard API writes.
7. If the connection test succeeds, upsert dashboards with stable IDs derived from the evaluation id or scenario name and timestamp.

Recommended dashboard outputs:

```text
dashboards/
  README.md
  hypothetest-overview.dashboard.json
  hypothetest-diagnostics.dashboard.json
  data/
    measurements.toon
  elasticsearch/
    index_template.yml
```

Prefer inline ES|QL visualization panels in dashboard definitions. Build dense operational dashboards with primary KPIs and key trends above the fold. Use descriptive chart titles, no markdown header panels, and time ranges that cover the evaluation run.

### Dashboard content

Create an overview dashboard when normalized metrics or comparisons exist:

- total runtime and per-variation runtime
- primary metric baseline/candidate comparison
- delta percent by metric, phase, and candidate
- repeat-level metric distribution
- failed, missing, or partial phase counts
- confidence and caveat summary as data tables when represented as indexed fields

Create a diagnostics dashboard when `esdiag` results data streams are available:

- cluster, node, index, shard, segment, cache, snapshot, repository, and search/indexing diagnostics relevant to the scenario
- diagnostic changes across variation, phase, repeat, and collection point
- links or fields identifying the preserved raw `esdiag` bundles

Do not duplicate `esdiag` documents into a custom Hypothetest index. Query the data streams produced by `esdiag process` directly.

### Custom evidence indexing

Only index custom Hypothetest evidence when the needed dashboard data is not already in `esdiag` results data streams or another declared Elasticsearch destination.

Use `espipe` for custom ingestion. Provide:

- an index template or composable template with correct field types for Kibana visualizations; start from `index_template.yml`
- a TOON measurement file derived from normalized analysis artifacts, preserving links back to source artifacts

Store custom measurement documents in this shared data stream:

```text
metrics-measurement-hypothetest
```

Never create a unique measurement data stream per evaluation. Use the document-level `evaluation` keyword for dashboard filters and cross-run comparison.

Conform custom measurement documents to `measurement-schema.md`. Keep local measurement artifacts compact and human-readable. Do not expand natural fields into ECS field paths:

- `@timestamp` is the measurement timestamp or best available evaluation timestamp.
- `evaluation` is the stable top-level keyword used to filter all documents from one evaluation.
- `scenario`, `deployment`, `variation`, `repeat`, and `phase` are natural benchmark dimensions.
- `metric`, `value`, `unit`, `source`, and `status` are natural metric fields.
- `baseline`, `candidate`, deltas, and confidence are natural comparison fields.
- `data_stream.*` is defined in the index template as constant keywords for the shared stream identity.

Use [measurement-schema.md](measurement-schema.md) for required fields, comparison fields, types, and data stream mappings.

### Measurement transform

The Analyst is the transform boundary for custom measurement documents:

1. Read local evidence from `evaluation.yml`, optional `manifest.toon`, `summary.toon`, `comparison.toon`, phase outputs, Rally outputs, espipe outputs, API output, shell output, and Python output.
2. Extract source-specific facts without changing their meaning.
3. Normalize extracted run values into the wide `runs[...]` TOON shape and
   comparisons into the `comparisons[...]` shape.
4. Unpivot each wide run only at the dashboard-ingestion boundary, producing
   one compact measurement row per non-null metric as required by
   `measurement-schema.md`.
5. Write the rows to `dashboards/data/measurements.toon`.
6. Ingest that TOON file with espipe's native TOON input support into `metrics-measurement-hypothetest` after the template is ready.

Keep business logic in the Analyst transform. Do not add an ECS-compatibility ingest pipeline. If an evaluation needs an ingest pipeline for source-specific cleanup, keep it limited to that cleanup and do not use it to rename fields into ECS paths.

Do not transform `esdiag` documents into `metrics-measurement-hypothetest`. When `esdiag process` has shipped diagnostics to Elasticsearch, dashboards must query those `esdiag` data streams directly and use `metrics-measurement-hypothetest` only for Hypothetest run-level measurements that are not already indexed elsewhere.

Every generated measurement document must preserve:

- the evaluation filter key through top-level `evaluation`
- benchmark dimensions as compact `scenario`, `deployment`, `variation`, `repeat`, and `phase` fields
- numeric metric data as compact `metric` and `value` fields
- a source artifact path when the value came from a local artifact

Record custom ingestion decisions in `dashboards/README.md`, including the target index or data stream, template path, source TOON path, espipe command used or recommended, and whether ingestion was actually executed.
