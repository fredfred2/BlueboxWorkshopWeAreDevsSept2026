# Rules for this stack

The second table of the plan: where each Hard rule that binds the chosen recipe gets the
value you resolved, before the question is asked.

**Rules for this stack** closes the plan: a second table, one row per Hard rule that
binds the chosen recipe, each row carrying the value you resolved - `rule | binds here
| resolved value`. Rows, not prose; a rule that does not bind the recipe gets no row,
and a row you cannot fill means the plan is not ready to ask. Candidate rows: 3 (the
zero-code package chosen, or why an SDK); 4, level 3 only (the logger bridged, by name);
7 (the exporter packages by name, the protobuf ones: Node's `*-otlp-proto` and never its
`*-otlp-http` (JSON), Python's `opentelemetry-exporter-otlp-proto-http`, and the two env
vars); 8 (the consumer the `Authorization` value goes into and the quoting that consumer
needs - quoted in a sourced `.env`, either quote in a compose `env_file`, unquoted in a
Docker `--env-file`; the value never read); 9 (each pinned version with the `npm view` /
`pip index` line it came from); and for SDK recipes one row labeled `SDK`: the metric
reader (level 2 and up) and the log processor (level 3) by class name. Services on one
recipe share a row; a row that differs by service names it. A Go plan at level 1 in a
compose stack has four rows (values illustrative - yours come from the lookup):

| rule | binds here | resolved value |
|---|---|---|
| 3 | no zero-code for Go; SDK, the registry covers `net/http` and `database/sql` | `go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp`, `github.com/XSAM/otelsql`; exporters left to `go.opentelemetry.io/contrib/exporters/autoexport` |
| 7 | `autoexport` takes the protocol from env, no exporter constructed | `OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf`, `OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=delta` |
| 8 | compose `env_file: .env` | `OTEL_EXPORTER_OTLP_HEADERS` in `.env`, unquoted (a compose `env_file` strips either quote); value never read |
| 9 | `go 1.22` in `go.mod`; newest contrib line that supports it | `…/otelhttp v0.58.0`, `…/autoexport v0.58.0`, `github.com/XSAM/otelsql v0.36.0`, one `go list -m -versions <module>` each |

A Node SDK plan at level 3 has six (values illustrative - yours come from the lookup):

| rule | binds here | resolved value |
|---|---|---|
| 3 | SDK: an in-house RPC layer nothing in the registry covers; bootstrap `src/otel.js` | `@opentelemetry/sdk-node` + `@opentelemetry/auto-instrumentations-node` for HTTP and pg |
| 4 | winston 3 in `src/logger.js`; the instrumentation injects the transport | `@opentelemetry/winston-transport`; no `OpenTelemetryTransportV3` by hand |
| 7 | exporters constructed in `src/otel.js`, so the package picks the wire format | `@opentelemetry/exporter-trace-otlp-proto`, `@opentelemetry/exporter-metrics-otlp-proto`, `@opentelemetry/exporter-logs-otlp-proto`; no `*-otlp-http` in `package.json`; `OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf`, `OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=delta` |
| 8 | `.env` sourced by `npm start` | `OTEL_EXPORTER_OTLP_HEADERS` in `.env`, quoted (the shell strips the quotes); value never read |
| 9 | `engines.node >=18` in `package.json`; newest line that supports it | `@opentelemetry/sdk-node 0.203.0`, `@opentelemetry/auto-instrumentations-node 0.80.0`, `@opentelemetry/exporter-trace-otlp-proto 0.203.0`, `@opentelemetry/exporter-metrics-otlp-proto 0.203.0`, `@opentelemetry/exporter-logs-otlp-proto 0.203.0`, `@opentelemetry/winston-transport 0.14.0`, one `npm view <package> version` each |
| SDK | metric reader and log processor `src/otel.js` wires | `PeriodicExportingMetricReader`, `BatchLogRecordProcessor` |

**Placement.** The rules table follows the plan table in both paths: before the question
when one is asked, before the "Taking level N" line when not; never folded into either.
Headless, the printed order is the plan table, the rules table, then the one line
"Taking level N (<what it yields>): <why>".
