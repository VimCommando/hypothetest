# Environment binding

## Environment binding — script generation

After readiness validation, generate the environment-specific scripts that
evaluation.sh calls. This is template-stamping from readiness findings, not
creative authoring — the Coordinator reads readiness.toon and the plan, then
selects and fills patterns from the reference catalog.

### Generated scripts

| Script | Purpose | Reference |
|---|---|---|
| `generated/scripts/compose-up.sh` | Start cluster (compose target) | compose templates |
| `generated/scripts/compose-down.sh` | Stop cluster (compose target) | compose templates |
| `generated/scripts/k3s-install.sh` | Install k3s (kubernetes target, provider: k3s) | `tools/k3s.md` |
| `generated/scripts/k3s-uninstall.sh` | Remove k3s (kubernetes target, provider: k3s) | `tools/k3s.md` |
| `generated/scripts/eck-up.sh` | Start cluster (kubernetes target) | `eck-templates.md` |
| `generated/scripts/eck-down.sh` | Stop cluster (kubernetes target) | `eck-templates.md` |
| `generated/scripts/sample.sh` | During-phase observation | `script-templates.md` |
| `generated/scripts/reset.sh` | Variation reset (delete indices, clear caches) | calling convention contract |
| `generated/scripts/load.sh` | Dataset loading wrapper | calling convention contract |

Also generate `generated/compose/` (compose.yml, .env, elasticsearch.yml)
or `generated/eck/` (namespace.yaml, elasticsearch.yaml, optionally
kibana.yaml) for the declared deployment target.

### Script calling convention

Use the [shared calling convention](execution-contract.md#generated-script-calling-convention) for every generated helper.

### sample.sh generation

When `diagnostics.during` is declared and profile is not `none`:

1. Read readiness.toon for platform, verified packages, tq availability
2. Resolve profile to method set (see `observation-methods.md`)
3. Select skeleton and collection functions from `script-templates.md`
4. Fill in only verified-package collection logic; omit unverified packages
5. Template `$ES_PID` resolution logic for the deployment target

When `diagnostics.during` is absent or `profile: none`, do not generate
sample.sh — evaluation.sh calls phase commands directly.

### Progressive loading

References are loaded based on deployment target, observation config,
and blueprint declarations. Each tool reference is self-contained — load
only the files relevant to the current blueprint.

#### Tool references (`tools/`)

**Always loaded:**
- `tools/curl.md` — ES API access
- `tools/ys.md` — schema validation
- `tools/toon.md` — structured summary output

**Loaded by blueprint condition:**
- `tools/espipe.md` — when the dataset loader or any phase uses `espipe`
- `tools/esdiag.md` — when `measure.diagnostics.tool: esdiag`
- `tools/rally.md` — when the dataset loader or any phase uses `rally`
- `tools/docker.md` — when `deployment.engine` resolves to `docker`
- `tools/podman.md` — when `deployment.engine` resolves to `podman`
- `tools/kubectl.md` — when `deployment.target: kubernetes`
- `tools/helm.md` — when `deployment.target: kubernetes`
- `tools/k3s.md` — when `deployment.kubernetes.provider` resolves to `k3s`
- `tools/tq.md` — when generating extraction helpers or active `diagnostics.during`

**Loaded by prescribed method or profile:**
- `tools/perf.md` — when `on_cpu` method is prescribed
- `tools/bpftrace.md` — when `off_cpu` method is prescribed
- `tools/sysstat.md` — when `standard` or `comprehensive` profile on Linux

#### Generation references

- **diagnostics.during active:** [script-templates.md](script-templates.md) for the sampling skeleton and collection catalog
- **target: compose:** compose template references
- **target: kubernetes:** `eck-templates.md` (CRD patterns, operator installation, service exposure)
- **diagnostics.during declared:** `observation-methods.md`

Load each target reference used by the plan, including both Compose and ECK for cross-target comparisons. For Compose assets read [compose-templates.md](compose-templates.md); for Kubernetes assets read [eck-templates.md](eck-templates.md).
