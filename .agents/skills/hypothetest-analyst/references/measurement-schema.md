# Hypothetest Measurement Schema

Custom Hypothetest measurement documents are stored in one shared data stream:

```text
metrics-measurement-hypothetest
```

Do not create a data stream per evaluation. Store the evaluation identifier in the top-level `evaluation` keyword and use it for dashboard filters.

## Scope

Use a Hypothetest-native schema. Do not force measurement documents into ECS field paths.

The only ECS-style fields required for indexing and Kibana time/data stream behavior are:

```text
@timestamp
data_stream.type
data_stream.dataset
data_stream.namespace
```

`data_stream.*` should be mapped as `constant_keyword` in the index template. Measurement artifacts do not need to repeat `data_stream.*` columns; the template or ingestion target defines the stream identity.

## Transform workflow

Use the [dashboard workflow](dashboards.md#measurement-transform) for extraction and ingestion order. Unpivot the [wide run table](metric-normalization.md) only at this ingestion boundary. Produce one measurement document per non-null metric, with its phase, source, unit, run status, and artifact provenance. Keep missing-value status in the wide source and report; do not invent numeric documents for missing metrics.

Do not use an ECS-compatibility ingest pipeline that renames natural fields into nested ECS-style paths. If a pipeline is needed for an unusual evaluation, keep it limited to evaluation-specific parsing or cleanup.

Do not transform `esdiag` results into this data stream. Query `esdiag` data streams directly when diagnostics were processed into Elasticsearch.

## Required fields

The `dashboards/data/measurements.toon` artifact uses these fields:

```text
@timestamp
evaluation
scenario
started_at
completed_at
deployment
variation
repeat
phase
metric
value
unit
source
status
artifact
```

Optional comparison fields:

```text
baseline
candidate
delta_absolute
delta_percent
confidence
```

## Mapping standards

Map fields consistently across all evaluations:

```text
@timestamp: date
data_stream.type: constant_keyword
data_stream.dataset: constant_keyword
data_stream.namespace: constant_keyword
evaluation: keyword
scenario: keyword
started_at: date
completed_at: date
deployment: keyword
variation: keyword
repeat: integer
phase: keyword
metric: keyword
value: double
unit: keyword
source: keyword
status: keyword
artifact: keyword
baseline: keyword
candidate: keyword
delta_absolute: double
delta_percent: double
confidence: keyword
```

Use `text` only for long report prose or caveat explanations, and add a keyword subfield only when the value must be grouped or filtered in Kibana.

## Data stream constants

The shared data stream identity is:

```text
data_stream.type: metrics
data_stream.dataset: measurement
data_stream.namespace: hypothetest
```

The composable index template for `metrics-measurement-hypothetest` should define those fields as `constant_keyword`. Do not add `ecs.*`, `event.*`, `metric.*`, or `hypothetest.*` fields unless a future dashboard requirement clearly needs them.

Allow dynamic fields because some evaluations capture scenario-specific measurements or dimensions. Apply conservative dynamic template defaults:

- strings map to `keyword`
- unexpected numeric fields are stored but not indexed
- unexpected booleans are stored but not indexed

Declare a field explicitly when it needs Kibana filtering, grouping, or numeric aggregation.

## Template expectations

The analyst should generate or reuse a composable index template for `metrics-measurement-hypothetest` that:

- maps `@timestamp` as `date`
- maps `data_stream.*` as `constant_keyword`
- maps identifiers and dimensions as `keyword`
- maps `repeat` as `integer`
- maps `value`, `delta_absolute`, and `delta_percent` as `double`
- allows dynamic fields for evaluation-specific measurements
- maps dynamic strings as `keyword`
- maps dynamic numeric and boolean fields with `index: false`
- avoids evaluation-specific templates, pipelines, or data streams

Use `index_template.yml` as the starting template artifact. Copy it to `dashboards/elasticsearch/index_template.yml` or pass it directly to espipe when the default fields are sufficient.

If the template already exists, reuse it unless the schema has changed.
