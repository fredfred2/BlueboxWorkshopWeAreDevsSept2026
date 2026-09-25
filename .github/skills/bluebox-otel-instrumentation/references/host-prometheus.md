# Host/Prometheus/log/datastore collection

Follow only when the user wants Bluebox to ingest telemetry a service's own SDK doesn't emit - host metrics, an existing Prometheus `/metrics`
endpoint, log files, or datastore/middleware metrics (PostgreSQL, MySQL, Redis, …). A **Collector deployment**, not repo-local SDK wiring, shipped
over the **same** OTLP endpoint and ingest token the main skill already uses.

For Kubernetes cluster/node/pod telemetry, use the "Kubernetes cluster monitoring" section above. This is for host-level and app-adjacent collection
(a VM/host agent, a sidecar, or a small standalone collector), not cluster monitoring.

## What this gives Bluebox

- **`hostmetrics`** - host CPU, memory, disk, filesystem, network, and load from the collector's machine; the OTel path to host metrics without
  OneAgent.
- **`prometheus`** - scrape a service's existing Prometheus `/metrics` endpoint and forward it.
- **`filelog`** - tail app/container log files and ship them as OTLP logs, for services that write to files instead of emitting OTel logs.
- **datastore receivers** (`postgresql`, `mysql`, `redis`, …) - metrics from managed or self-hosted datastores and middleware.

## Boundaries and gates

- **App instrumentation is unchanged.** Adds host/scrape/log/datastore telemetry alongside per-service SDK instrumentation; app services keep
  exporting their own traces/metrics/logs directly to Bluebox.
- **Same Bluebox ingest contract.** Export to the Bluebox OTLP endpoint with the Bluebox ingest token - no separate credential, no extra scope. Token
  from env/secret store; never inline or commit it.
- **Cumulative metric series need delta conversion.** Bluebox rejects cumulative metrics. `prometheus` and datastore receivers are predominantly
  cumulative counters, so their pipelines **must** include `cumulativetodelta`. `hostmetrics` is a **mix**: gauges (e.g. memory/filesystem
  utilization) need no conversion; cumulative sums (e.g. `system.cpu.time`, `system.disk.io`, `system.network.io`) do. `cumulativetodelta` converts
  only cumulative sums and passes gauges through unchanged, so keep it on any pipeline with a cumulative source. Don't call host metrics "all
  cumulative." Logs (`filelog`) need no conversion.
- **Datastore credentials are privileged.** `postgresql`/`mysql`/`redis` receivers need a monitoring user/password. Use a least-privilege monitoring
  account; source credentials from secret/env. Never inline or commit them.
- **Confirm the target.** Only configure a receiver for a signal the user asked for and a source that actually exists (a real `/metrics` endpoint,
  real log paths, a reachable datastore). Do not speculatively enable receivers.

## Prerequisites

- A place to run the Collector: the host/VM being monitored (for `hostmetrics`/`filelog`), a sidecar, or a small standalone collector that can reach
  the scrape/datastore targets.
- The **OpenTelemetry Collector Contrib** distribution (or any build with the `hostmetrics`, `prometheus`, `filelog`, and datastore receivers plus the
  `cumulativetodelta` processor).
- The Bluebox OTLP endpoint. Run `bluebox otlp-endpoint` if unknown (main skill: exit-code handling).
- The Bluebox ingest token, supplied by the user via env or a secret store. You never fetch, print, or commit it.

## Collector configuration

Enable only the receivers the user asked for; this example shows all four. Drop the ones you don't need (and their pipeline entries).

```yaml
extensions:
  health_check:
    endpoint: 0.0.0.0:13133

receivers:
  hostmetrics:
    collection_interval: 30s
    scrapers:
      cpu: {}
      memory: {}
      disk: {}
      filesystem: {}
      network: {}
      load: {}
  prometheus:
    config:
      scrape_configs:
        - job_name: app
          scrape_interval: 30s
          static_configs:
            - targets: ["127.0.0.1:9464"]         # the app's existing /metrics endpoint
  filelog:
    include: ["/var/log/app/*.log"]               # real log paths only; confirm no credentials or PII before enabling
    include_file_path: true
    # add operators here only if you must parse structured fields; preserve event timestamps
    # IMPORTANT: before enabling, confirm log content does not include credentials, tokens, or PII —
    # log files are shipped verbatim. If sensitive content may appear, disable this receiver for
    # that log path and use SDK-side log export (Hard rule 4) instead.
  postgresql:
    endpoint: ${env:POSTGRES_ENDPOINT}            # host:port
    username: ${env:POSTGRES_MONITOR_USER}
    password: ${env:POSTGRES_MONITOR_PASSWORD}
    tls:
      insecure: false

processors:
  resourcedetection:
    detectors: [env, system]                      # adds host.name and OS attributes
  cumulativetodelta:
    max_staleness: 25h                            # keep above the collection/scrape interval

exporters:
  otlphttp/bluebox:
    endpoint: ${env:BLUEBOX_OTLP_ENDPOINT}                     # from `bluebox otlp-endpoint`
    headers:
      Authorization: ${env:BLUEBOX_OTLP_AUTH}                 # whole header value incl. scheme; from env/secret, never inlined

service:
  extensions: [health_check]
  pipelines:
    metrics:
      receivers: [hostmetrics, prometheus, postgresql]
      processors: [resourcedetection, cumulativetodelta]
      exporters: [otlphttp/bluebox]
    logs:
      receivers: [filelog]
      processors: [resourcedetection]
      exporters: [otlphttp/bluebox]
```

Notes:

- The exporter uses OTLP over `http/protobuf` to the Bluebox OTLP endpoint, same transport contract app instrumentation already uses.
- Keep `cumulativetodelta` on any metrics pipeline carrying a cumulative source (`prometheus`, datastore receivers, the cumulative-sum series from
  `hostmetrics`). Without it Bluebox rejects those series and they silently don't appear; gauges are unaffected either way.
- Set a stable `service.name`/host identity so this telemetry lines up with instrumented services - e.g. via `resourcedetection` plus
  `OTEL_RESOURCE_ATTRIBUTES` on the collector, or a `transform` processor. Don't invent a name that conflicts with an existing service identity.
- Add datastore receivers (`mysql`, `redis`, …) the same way: a least-privilege monitoring credential from env/secret, routed through the
  `cumulativetodelta` metrics pipeline.

## Required environment

Provide the endpoint, auth header, and any datastore credentials via env/secret store. Never inline:

```bash
export BLUEBOX_OTLP_ENDPOINT="<bluebox otlp-endpoint output>"
# The WHOLE Authorization value, scheme included, copied from the Bluebox Setup page (Hard rule 8):
# "Bearer <token>" for a platform token (dt0s16…), "Api-Token <token>" for a classic one (dt0c01…).
export BLUEBOX_OTLP_AUTH="<supplied by the user; keep out of tracked files>"
# only if a datastore receiver is enabled:
export POSTGRES_ENDPOINT="db-host:5432"
export POSTGRES_MONITOR_USER="<least-privilege monitoring user>"
export POSTGRES_MONITOR_PASSWORD="<from secret store>"
```

In Kubernetes, mount these from a `Secret` (as in the Kubernetes section above) rather than env literals.

## Verify

- Start the collector; confirm `health_check` is healthy and the collector isn't erroring on export (a `401/403` means the ingest token isn't reaching
  the collector - secret/config issue, not code).
- The header lives in the collector's configuration, where you cannot test it: before the `bluebox ask`, ask whether it is set and take the answer, as Workflow step 4 does for a variable in the user's terminal. No header is `blocked` (`no_token`), nothing asked.
- Ask Bluebox whether the new telemetry is arriving, e.g.:

  ```bash
  bluebox ask "are host CPU/memory metrics arriving for host <host> in the last 15 minutes?"
  bluebox ask "are metrics from the app /metrics scrape arriving in the last 15 minutes?"
  ```

- Report per the closing summary's three states: no answer from `bluebox ask` means `blocked` (`verify_unreadable`), never verified. Missing metrics:
  check `cumulativetodelta` first.

## Report

Summarize: which receivers were enabled and why, the sources they target (host, `/metrics` endpoint, log paths, datastore), that metrics pipelines
include `cumulativetodelta`, that credentials stayed in env/secret and were never committed, and verification status (verified vs blocked).
