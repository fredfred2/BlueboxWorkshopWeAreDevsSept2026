# Run it, then verify

Workflow steps 5 and 6: the run offer, the exporter log read, the settle, the ONE batched
`bluebox ask`, the follow-up rules and the secrets scan. `scripts/verify.sh` in this
skill's directory runs the two commands of this file with their guards built in
(`bash <skill dir>/scripts/verify.sh logs …` for the exporter read, `… ask …` for the
batched check; `--help` prints the arguments). It is a plain file with no executable bit:
always through `bash`.

## The run offer

Nothing can arrive from an app that never ran. If the question did not grant the run, offer
it after wiring and build-verify: name the start command from the inventory, say what it
will do - start the stack, send one request to each instrumented service (through the
reverse proxy where there is one), wait for the settle interval, verify once - and ask
before starting anything. One request per service is enough.

If the user declines, or no user is present and you cannot start the stack, stop there:
those services are `blocked`, their detail opening with `user_declined —` when the developer
declined, else with the one reason-set token that stopped you (`no_token`, `no_endpoint`,
`unbuildable_on_host`, …, or `other: <text>`) - never a bare sentence - followed by the
runnable command, secrets replaced by placeholders (`--env-file .env.otel`, `$DT_TOKEN`),
and next steps repeats it. Do not verify an app that is not running, and never report
`reporting` for a service you saw no signal from.

A containerized stack on a host whose probe found no usable runtime has no run and no
verification: skip this section, do not offer the run, do not go looking for a runtime
(Hard rule 12). Those services are `blocked` (`no_runtime — no docker, podman or nerdctl
daemon reachable; start or install one, then the plan's start command`), and Next steps carries
that start command plus the verification command. `build_failed` is for a build that ran.
Services the reachability line closed `registry_unreachable` or `endpoint_unreachable`
(Workflow step 1) skip this section the same way, whatever the question granted.

Verification happens EXACTLY once, after all wiring and the traffic window, and only with
the ingest header present (Workflow step 4). Build-verify (Hard rule 9) is compile/test
only. Without the header nothing in the Workflow runs - no stack, no traffic, no local receiver, no
`bluebox ask` - and the service is `blocked` (`no_token — <file> has no Authorization
value`), never `reporting`; a service never exercised is `blocked` too.

## Read the exporter before you wait

The SDK writes each export's outcome to its own log
within seconds of the request; the settle wait and the ask are for what Bluebox holds, not
for whether the export left, and a 415 or a missing metrics reader read from the log costs
seconds where the ask costs a cycle. So the verification start of Workflow step 5 also
carries the language's diagnostics switch (the table in
[language-traps.md](language-traps.md)), set the same way as the export knobs of
that step and per service: prepended to the one-off start command (`OTEL_LOG_LEVEL=info
OTEL_METRIC_EXPORT_INTERVAL=10000 … <start command>`) or added next to the knobs in the
same throw-away compose `environment` - that one start only: the committed run command
never carries it, and the final state carries none of it, so it leaves with the knobs - and
after the one request per service you read the export lines before any wait.

Read the lines ~20 s after the request (the knobs of step 5 make every signal export within
10 s) with a bounded wait (Hard rule 11), and never the whole log: grep the status lines and
drop anything that could carry a header, cut the query string and user-info out of any URL
left and mask a Dynatrace token and an Authorization, Api-Token, Bearer, Basic or OTLP
headers value as `scripts/state-update.py` would refuse it (Hard rule 1: a token placed in the
endpoint URL, against Hard rule 8, must not reach the transcript). `bash <skill dir>/scripts/verify.sh logs
--lang <language> --service <name> --compose "<compose>"` is that read: it runs
`<compose> logs --since 2m <service> 2>&1 | grep -ai <grep> | grep -viE 'authorization|header'`
with the row's `-e` list from the diagnostics table in place of `<grep>` and pipes the result
through its `mask` sed filter; pass `--logs-cmd` instead of `--compose` for `kubectl logs`,
a journal or the process's stderr on a stack that is not compose. A failure line that
mentions a header is never shown, only counted (`<N> failure line(s) … withheld`): the
transport is not confirmed, so take it as the 401 or 403 row below. An empty read
is evidence only when the log command itself succeeded: run it once without the greps and
with both streams discarded (`<compose> logs --since 2m <service> >/dev/null 2>&1`, the
.NET `exec … cat` the same way, never printing the file) and a non-zero exit (wrong
service name, container gone, no log file yet) is a run problem to fix, never a clean
transport and never `signal_unwired`. Then map what you read, per service and per selected
signal:

| the log says | it means | do, then restart and read again |
|---|---|---|
| no failure line after two export intervals (success is silent in every SDK, and none logs a plain attempt) | the transport is right | go to the settle wait |
| 401 or 403 (`Unauthorized`, `Forbidden`) | the `Authorization` value or its scheme (Hard rule 8) - never print it: re-test presence with the step 4 grep and have the user paste the whole value again | still rejected → `auth_rejected` |
| 415 (`Unsupported Media Type`) | JSON on the wire where ingest takes `http/protobuf` only (Hard rule 7): a JSON protocol setting, an exporter the code constructs (a Node `*-otlp-http` package fails the exporter guard of Hard rule 9 before verification starts) | set the protocol to `http/protobuf` everywhere it is set, or construct no exporter and let the variable choose; restart or rebuild; still 415 → `wire_rejected` |
| 404 (`Not Found`) | the endpoint path: the value is not what step 2 printed (a per-signal URL in the generic variable, `/v1/<signal>` already appended) | set it verbatim; still 404 → `endpoint_rejected` |
| name resolution failed (`ENOTFOUND`, `UnknownHostException`, `no such host`) | the endpoint host: the value is not what step 2 printed | set it verbatim; still failing → `endpoint_rejected` |
| connection refused or timed out on the host step 2 printed | the network, not the config | `egress_blocked`, naming host and port in the detail |
| the code registers no provider, reader or bridge for a selected signal (the Java agent wires every signal unless its exporter is `none`) - a silent log never shows this, the code does | that signal is not wired: no metrics reader, no log bridge, no provider | back to Workflow step 3 for that signal; still absent → `signal_unwired` |

Fix, restart, read again - before any settle wait; a retry after a fix starts here, at the
log read, never at the ask. The ask stays single: it runs once, after every selected signal
of every selected service shows no failure line or carries the token that stops it, and a
signal the code shows as unwired is not a verifier miss to re-ask for. If the repo's
committed run command picked up the switch or the knobs, take them out before the closing
summary.

## Settle, then ONE batched ask

With no failure line left for any selected signal, wait ~45 s after the traffic when the export knobs of
Workflow step 5 are set and no logs are in scope, ~90 s otherwise (the SDK exports metrics every 60 s without the knobs, and
log ingest lags spans regardless), then run ONE batched check covering every
selected service and only the signals the user selected, minus per-service drops under
Hard rule 4. The window runs from the traffic start to the moment you ask - never narrowed
to the burst: metric points are stamped at export time.

```bash
bluebox ask --env <env> "For the window <T1>..<now>: which of these services have <the
signals the user selected — e.g. spans, logs, and metrics> arriving — <service list>?
Count by OTLP service.name, not by entity. For metrics: FIRST list every metric key that
carries that service.name in the window (the catalog for that service - do not test guessed
key names or prefixes), then judge from that list; any key the app exported counts -
request, client-side (http.client.*), runtime, JVM - but list dt.* and other entity-derived
keys separately and do not count them: dt.service.request.count/failure_count/response_time
are derived from spans and exist for every service with inbound request spans. List
per-service signals, the metric keys seen, and the values of vcs.repository.url.full on
their spans."
```

`<env>` is the plan table's environment name - the `deployment.environment.name` every
service exports - one value, read from one place; never a second spelling here
(`bash <skill dir>/scripts/verify.sh ask --env <env> --window "<T1>..<now>" --services "…" --signals "…"`
runs exactly this prompt). The counts the closing summary reports are this scoped ask's:
an unscoped `bluebox ask` counts across every environment the workspace holds and answers
differently, so every count you quote names its scope (`--env <env>`), and a scoped count
is never compared with an unscoped one.

Spans present but "metrics absent" is usually a verifier miss (outbound-only or batch
services have only client, runtime or JVM series) when the log showed no metrics export
failure; where the code registers no metrics reader it is `signal_unwired`, not a miss. The one allowed
follow-up ask, after one more settle, names the expected keys for the missing services;
what is still missing is `blocked` (`verify_absent —` with the evidence you have); do not
loop. Derived `dt.*` keys
never fill that gap: at level 2 or 3, a service with spans and only derived keys after the
follow-up is `blocked` (`verify_absent — only derived dt.service.* keys`), never
`reporting`. A `vcs.*` mismatch
is a warning when the signal arrived. No token, or no endpoint? Workflow step 4 stopped
you before this section: `blocked` (`no_token — …`, `no_endpoint — …`) and the exact
verification command for later.

## Metric keys per runtime

Judge the catalog against the keys the runtime's HTTP instrumentation emits - that list,
not a guess, is what "metrics arriving" means at level 2 or 3. Either the older or the
stable semconv name counts; which one appears depends on the instrumentation line and
`OTEL_SEMCONV_STABILITY_OPT_IN`:
- Node (`@opentelemetry/instrumentation-http`): `http.server.duration`, `http.client.duration`
  (`http.server.request.duration`, `http.client.request.duration` with
  `OTEL_SEMCONV_STABILITY_OPT_IN=http`)
- Java agent 2.x: `http.server.request.duration`, `http.client.request.duration`, `jvm.*`
- .NET auto-instrumentation: `http.server.request.duration`, `http.client.request.duration`
- Go `otelhttp`: `http.server.request.duration` (`http.server.duration` on older contrib lines)
- Python `opentelemetry-instrument`: `http.server.duration`, `http.client.duration`
  (`http.server.request.duration`, `http.client.request.duration` with the same opt-in)
An outbound-only or batch service shows only the client, runtime or JVM keys of its
runtime; a service with spans and none of its runtime's keys after the follow-up ask is
`verify_absent`.

## Before finishing

Scan tracked changes for secrets (`dt0c01.`/`dt0s16.` prefixes, real
`OTEL_EXPORTER_OTLP_HEADERS` values, userinfo-bearing URLs), then stop and remove what you
started. If the first window was blocked, offer the run again for a fresh one. Then the
closing summary ([closing-summary.md](closing-summary.md)).
