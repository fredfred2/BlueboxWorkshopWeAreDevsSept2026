# Language traps and recipes

Per-runtime knowledge: what zero-code covers, the log bridges that bite, the Node recipe,
the build caches, the exporter guard that runs after every green build, and the exporter diagnostics read at
verification. Read the first two sections when writing the plan table, the rest while
wiring and at Workflow step 5.

## Zero-code first, and never twice (Hard rule 3)

Prefer the language's auto-instrumentation
([zero-code setup](https://opentelemetry.io/docs/zero-code/): Java agent, .NET auto-instr,
`node --require` + auto-instrumentations, `opentelemetry-instrument`) and add code only
where the runtime needs it (Go, C++, bespoke frameworks); before an SDK recipe, confirm in
the [OTel registry](https://opentelemetry.io/ecosystem/registry/) that no library covers
the framework, HTTP client and database driver, and name the reason in the recipe column.
A service that already carries an SDK or agent gets neither a second one nor a second log
bridge. When services export to an in-stack collector, the plan has one row for that
collector. Add a Bluebox `otlphttp` exporter to its existing pipelines as
[export-contract.md](export-contract.md) says (http/protobuf, the token from the
environment only, `cumulativetodelta` on the metrics pipeline), through the repo's
extras/override config when it has one. The routed services are "verification only"
rows with no files. In the closing table the collector's row carries the state of the
services it routes: `reporting` when they report, else `blocked` with their reason. A
service exporting `direct:` to another backend gets an env-only change (endpoint, headers,
protocol) and a note that the old backend stops receiving unless the user asks for dual
export, which is a collector, not two exporters in the SDK. On Kubernetes,
annotation-based injection is the zero-code recipe only where an `Instrumentation`
resource the service can use **already exists** (`kubectl get instrumentations -A`; the
CRD alone proves nothing, and the annotation silently no-ops without one). Reference it
as `namespace/name` in the deployment entry; otherwise take the in-image recipe. Creating
the `Instrumentation` or installing the Operator is a cluster change and never part of
this run.

## Logs are additive (Hard rule 4)

Bridge the logger the service already uses (appender, hook, transport); sink, format,
timestamps, timezone and levels stay byte-identical, or that service stays at level 2 and
you say so. Before bridging, read what it logs: request or response bodies, credentials,
tokens or personal data (names, emails, account identifiers) in the records keep it at
level 2 (so does a wrapper logger or dynamic fields you cannot read), even when the
developer chose 3; name the service and the reason, and interactive, ask before bridging
it so the developer can raise it knowingly. Three known traps, checked while wiring: .NET
`ClearProviders()` discards the provider the auto-instrumentation injects. Remove only
the providers you replace; winston (v3+) exports nothing until
`@opentelemetry/winston-transport` is installed, and the winston instrumentation then
injects the transport itself into loggers created after it loads (`--require` order), so
do not also attach `OpenTelemetryTransportV3` by hand; Go `otelhttp` (contrib v0.66+)
re-applies its span-name formatter after the handler returns, so give the route at wrap
time with `otelhttp.WithSpanNameFormatter` (or `otelhttp.WithRouteTag` per route) and set
`http.route` there, never inside the handler.

## Node recipe

`@opentelemetry/sdk-node` + `@opentelemetry/auto-instrumentations-node`, loaded with
`node --require ./otel.js`, versions resolved under Hard rule 9. Four things the zero-code
path does not do for you:

- **Metrics need an explicit reader.** `NodeSDK` with only the endpoint set exports
  traces and nothing else — silently, no warning. Pass
  `metricReader: new PeriodicExportingMetricReader({ exporter: new OTLPMetricExporter() })`
  (`@opentelemetry/sdk-metrics`, `@opentelemetry/exporter-metrics-otlp-proto`) and set
  `OTEL_METRICS_EXPORTER=otlp` in the deployment entry.
- **Exporters are the `-proto` packages**, in `package.json` and in the bootstrap file:
  `@opentelemetry/exporter-trace-otlp-proto`, `@opentelemetry/exporter-metrics-otlp-proto`,
  `@opentelemetry/exporter-logs-otlp-proto`. The `-otlp-http` siblings send JSON and
  ingest answers 415 (Hard rule 7); the guard of Hard rule 9 fails the service while one
  is installed.
- **`@opentelemetry/instrumentation-console` is not in `auto-instrumentations-node`** and
  lives on its own version line (0.4.x at the time of writing, not the 0.5x–0.6x
  instrumentation line): its own
  package, its own `npm view` lookup, its own version in the plan table. A pin copied
  from a sibling (`^0.53.0`) fails `npm install`. Level 3 with `console.*` logging needs
  it; a winston or pino logger takes that logger's bridge instead (Hard rule 4).
- **Metric keys to expect** at verification: `http.server.duration` and
  `http.client.duration` (the per-runtime list in [verify.md](verify.md)).

## Read-only source (Inventory)

A compose entry that mounts the service's source tree read-only (`:ro`, or
`read_only: true` on the bind mount) is a plan-row fact, not a build-time surprise: new
packages cannot be installed into that tree at start, so they go into the image — the row
names the Dockerfile (existing, or new: "needs a Dockerfile") among the files that change,
and the start command rebuilds.

## Build caches (Hard rule 9)

Build or run in a container when the host gates its toolchains, and mount a named volume
for the module or package cache so a repeated run never downloads twice (Go
`-v bluebox-gomod:/go/pkg/mod`, Node `-v bluebox-npm:/root/.npm`, Maven
`-v bluebox-m2:/root/.m2`, .NET `-v bluebox-nuget:/root/.nuget/packages`, Python
`-v bluebox-pip:/root/.cache/pip`); create it if missing, never remove it.

## Exporter guard (Hard rule 9)

A green build is not the whole check: before recording the service, run the exporter
guard for its runtime, and a guard hit is `build_failed` until fixed. Node — the
manifest and the bootstrap file must carry no JSON exporter (Hard rule 7):
`grep -nE 'exporter-(trace|metrics|logs)-otlp-http([^a-z-]|$)' -- package.json '<bootstrap file>'`
(the file name comes from the repo: keep the single quotes and the `--`, and a name with
anything outside `A-Za-z0-9._/-` is not run — record `build_failed` naming it)
— exit 1 with nothing printed is the only pass; a line printed (exit 0), or exit 2
because a named file is missing, fails the service: remove the package, add the
`-proto` sibling, rebuild (or name the bootstrap file the plan row lists).
Not `npm ls --all`: `@opentelemetry/sdk-node` depends on every exporter, so that lists
the JSON ones in every project. Python — the manifest must name the protobuf exporter, or
the `opentelemetry-exporter-otlp` umbrella that carries it:
`cat requirements*.txt pyproject.toml 2>/dev/null | grep -qE 'opentelemetry[-_]exporter[-_]otlp([-_]proto[-_]http)?([^a-z-]|$)'`
— a non-zero exit fails the service (`-proto-grpc` alone is not it).

## Exporter diagnostics per runtime

The verification start of Workflow step 5 carries the language's diagnostics switch
below, set the same way as the export knobs of that step and per service
([verify.md](verify.md) says when to read the lines and what they mean). Each row names
the level that does not print request headers (Hard rule 1); where that is unconfirmed
for the SDK the row stays at its default level and reads failure lines only. Check the
row against the SDK version the plan pinned before relying on a line.

| language | first-start switch | what the log gives | grep |
|---|---|---|---|
| Node (`sdk-node`, exporters 0.2xx) | `OTEL_LOG_LEVEL=info`. The SDK registers its console diag logger from it; `info` prints the export failures and no payload, the OTLP transports log no header at any level, and a rejected header value is echoed once by `Header "…" has invalid value`, which the filter below drops. `debug` would add one `items to be sent` line per export but also the export body (span attributes) into the container's log: do not set it | failures at info as `Export failed with non-retryable error: OTLPExporterError: <status text>` (`Unsupported Media Type`, `Unauthorized`, `Forbidden`, `Not Found` - the text, never the number), the metrics reader repeating it at error as `metrics export failed (…)`, a network error as `export request failure (error: …)`; success is silent and no attempt is logged, so a signal is wired only where the code registers its exporter, reader or bridge | `-e 'export failed' -e 'export request'` |
| Java agent | none: the agent logs `Failed to export <signal>s. Server responded with HTTP status code N` at its default level; `-Dotel.javaagent.debug=true` is unconfirmed on headers and floods the log, do not set it | failures per signal, with the number; success is silent, and every signal is wired unless its `OTEL_<SIGNAL>_EXPORTER` is `none` | `-e 'Failed to export'` |
| Python (`opentelemetry-instrument`) | none: the exporter's own logger reports failures at the default level; `OTEL_PYTHON_LOG_LEVEL=debug` raises the root logger and with it `urllib3`, which prints request headers, do not set it | `Failed to export … batch code: N` per signal; success is silent | `-e 'Failed to export' -e 'Transient error'` |
| .NET (auto-instrumentation) | `OTEL_DOTNET_AUTO_LOG_LEVEL` stays at its default `info` (`debug` is unconfirmed on headers) | the exporter's failures in the log file under `OTEL_DOTNET_AUTO_LOG_DIRECTORY` (`/var/log/opentelemetry/dotnet` by default), not on the container's stdout: read it with `<compose> exec <service> sh -c 'cat /var/log/opentelemetry/dotnet/*'` through the same greps and `sed`; success is silent | `-e 'Exporter failed' -e 'status code'` |
| Go | none: no env switch exists (`OTEL_LOG_LEVEL` is not read); the default error handler writes every failed export to stderr as `failed to send to <url>: 415 Unsupported Media Type` | failures per exporter; success is silent, and a signal is wired only where the code registers its provider | `-e 'failed to send'` |
