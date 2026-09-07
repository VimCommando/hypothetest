# tq

Read when generating JSON/YAML extraction or during-phase sampling. tq is the required extraction tool for Hypothetest-owned helpers; user-declared runtimes remain scenario-specific prerequisites.

Verify `tq --version` and inspect `tq --help` for the installed interface. If missing, use the workspace's declared installation source or report it as a setup blocker; do not substitute a Python runtime.

Preflight every generated filter with representative input. For example:

```bash
printf '%s\n' '{"status":"green"}' | tq -x -r '.status'
```

`-x` preserves unparseable diagnostic output. For numeric assignments, also validate the extracted value and fail the sample on invalid input; passthrough text is not a measurement. Archive original API responses before extraction.

For scalar shell assignments use `-r` to avoid TOON sequence framing. Use the installed filter set; the sampling examples retain fractional averages and do not require a rounding builtin.
