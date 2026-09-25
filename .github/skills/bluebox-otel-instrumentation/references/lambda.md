# AWS Lambda instrumentation

Follow only when the user asks Bluebox to instrument an **AWS Lambda function**, not a normal long-running service. Still app-code instrumentation,
but its freeze/thaw lifecycle changes how telemetry must be exported, so the main skill's default SDK setup isn't enough alone. Ships to the **same**
Bluebox OTLP endpoint and ingest token the main skill already uses.

## Why Lambda is different

- **The runtime freezes between invocations.** The execution environment freezes almost immediately after the handler returns. A `BatchSpanProcessor`
  that flushes on a timer or on process exit will lose buffered spans, because the process is frozen, not exited.
- **Cold starts matter.** Instrumentation must be ready before the first invocation; export must not add unbounded response latency.
- **You usually do not control process shutdown.** "Flush on exit" isn't a reliable delivery mechanism here.

The fix is one of the two paths below. Both guarantee spans flush before the environment freezes.

## Path A (recommended): AWS-managed OpenTelemetry Lambda layer

Add the AWS-managed OpenTelemetry Lambda layer (the `opentelemetry-lambda` / ADOT layer for the function's runtime). It provides auto-instrumentation
**and** an in-process Collector extension, and hooks the Lambda Telemetry API to flush on `runtimeDone` - the freeze-safe flush point.

Wiring:

- Attach the correct layer ARN for the function's runtime/region (pick the version from `open-telemetry/opentelemetry-lambda` releases; don't hardcode
  a stale ARN - look up the current one for the runtime/arch/region).
- Set the handler wrapper the layer documents (for example `AWS_LAMBDA_EXEC_WRAPPER=/opt/otel-instrument` for Node.js/Python).
- By default the SDK exports to the layer's in-process Collector extension at `http://localhost:4318`, which forwards to the backend. To send to
  Bluebox, give the extension a Collector config exporting to the Bluebox OTLP endpoint:
  - Provide a custom Collector config file and point the layer at it with `OPENTELEMETRY_COLLECTOR_CONFIG_URI` (newer layers; local path such as
    `/var/task/collector.yaml` or a remote URI) or `OPENTELEMETRY_COLLECTOR_CONFIG_FILE` (older layers).
  - The exporter block uses the Bluebox OTLP endpoint and ingest token in the `Authorization` header (export contract below).

Minimal Collector config for the extension (ship to Bluebox):

```yaml
receivers:
  otlp:
    protocols:
      http:
      grpc:
processors:
  batch:
exporters:
  otlphttp:
    endpoint: ${env:BLUEBOX_OTLP_ENDPOINT}
    headers:
      Authorization: ${env:BLUEBOX_OTLP_AUTH}   # whole header value incl. scheme, from a secret-backed env var
service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [otlphttp]
```

## Path B: SDK exports directly to Bluebox (no bundled Collector)

If not using the layer's Collector extension (or wiring the SDK by hand), point the SDK exporter directly at Bluebox and make export freeze-safe:

- Set `OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf`, `OTEL_EXPORTER_OTLP_ENDPOINT=<Bluebox OTLP endpoint>`, and
  `OTEL_EXPORTER_OTLP_HEADERS="Authorization=<value from the Bluebox Setup page>"` (secret-backed env var, never inlined). The scheme is part of that
  value and depends on the ingest-token kind; do not compose it here.
- Node.js: depend on `@opentelemetry/exporter-trace-otlp-proto` (and `-metrics-`/`-logs-` siblings), or let `@opentelemetry/sdk-node` pick an exporter
  from `OTEL_EXPORTER_OTLP_PROTOCOL`. A self-constructed `*-otlp-http` exporter ignores that env var and sends `Content-Type: application/json`, which
  ingest rejects with **415**.
- Do **not** rely on `BatchSpanProcessor` flush-on-exit. Call an explicit `forceFlush()` on the tracer/span processor before the handler returns, or
  use a Lambda-aware instrumentation wrapper that flushes on `runtimeDone`.
- Keep the exporter timeout well under the function timeout so a slow export can't hang the invocation.

Prefer Path A when the user just wants it to work; Path B is for functions with their own SDK bootstrap or that can't add a layer.

## Bluebox export contract (same as the main skill)

- Hard rules 1, 7 and 8 apply unchanged: `http/protobuf` to the Bluebox OTLP endpoint, delta temporality for metrics, the `Authorization` value whole
  as the Setup page shows it, held in a Lambda environment variable backed by a secret and never committed anywhere.

## Resource attributes for Lambda

Set service identity plus Lambda/cloud resource attributes so Bluebox lines the function up with the rest of your services:

- `service.name` - the logical service (via `OTEL_SERVICE_NAME`).
- `cloud.provider=aws`
- `cloud.platform=aws_lambda`
- `cloud.resource_id=<function ARN>` - the full `arn:aws:lambda:<region>:<account>:function:<name>`.
- `faas.name=<function name>` and `faas.version=<version or alias>`.

The layer sets several of these automatically; add any missing via `OTEL_RESOURCE_ATTRIBUTES`. Don't overwrite a correct auto-detected value with a
guessed one.

## Verify

The header lives in the function's configuration, where you cannot test it: before the invocation, ask whether it is set and take
the answer, as Workflow step 4 does for a variable in the user's terminal. No header is `blocked` (`no_token`), nothing invoked.

Invoke the function to generate at least one known request, note the wall-clock time and `OTEL_SERVICE_NAME`, then verify through Bluebox:

```bash
bluebox ask --service <OTEL_SERVICE_NAME> --env <env> "are spans arriving for <function> around <recorded-test-time>?"
```

Report per the closing summary's three states: no token (`no_token`, nothing invoked) or no workspace (`no_endpoint`) is `blocked`
before the invocation; no answer from `bluebox ask` is `blocked` (`verify_unreadable`); never verified.

## Boundaries

- Does not set up cloud-provider managed-service monitoring, Lambda platform metrics from the provider, RUM, AppSec, or dashboards/alerts. It
  instruments the function's own traces (and, optionally, metrics/logs) to Bluebox.
- No observability-backend configuration is involved; everything flows through the Bluebox OTLP endpoint.
