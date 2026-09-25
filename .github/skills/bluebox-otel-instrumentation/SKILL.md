---
name: bluebox-otel-instrumentation
description: >
  Use when asked to instrument a service or repository with OpenTelemetry so its telemetry
  flows to Bluebox, or when a `.env.otel.bluebox-template` file is in the repo. Do NOT use
  for OpenTelemetry setups that target a non-Bluebox backend (e.g. exporting to Jaeger,
  Datadog, or a self-hosted collector): that is generic OTel work, not this skill.
  Triggers: "add OpenTelemetry", "instrument this service", "instrument this repo", "set up
  tracing", "OTel setup", "wire up telemetry for Bluebox", ".env.otel.bluebox-template".
compatibility: Coding agents (Claude Code, Cursor, Windsurf, Copilot, Kiro, OpenCode, Codex)
metadata:
  version: "3.0.0"
  audience: coding-agent
---

# Bluebox OTel Instrumentation

You already know OpenTelemetry. This skill does not teach it. It carries the Bluebox
contract and the discipline that turns wiring into verified coverage.

This file is the hub: the order, the Hard rules and the Workflow, each once, complete on
its own. A reference carries a rule's full text or an on-request recipe, never a rule this
file lacks, so a reference or script missing on disk (older CLIs deliver this file alone)
blocks nothing. Read a reference when the table says so, not from memory.

## Read this reference when

| reference | read it when |
|---|---|
| [export-contract.md](references/export-contract.md) | before the plan table (Hard rules 1, 2, 5–8 in full) and at steps 2 and 4 |
| [probes.md](references/probes.md) | inventory (runtime probe); after approval (reachability line) |
| [language-traps.md](references/language-traps.md) | the plan table (Hard rules 3 and 4 in full) and wiring: Node recipe, build caches, exporter guard and diagnostics |
| [rules-table.md](references/rules-table.md) | closing the plan: the worked examples |
| [session-discipline.md](references/session-discipline.md) | Hard rules 11 and 12 in full |
| [state-resume.md](references/state-resume.md) + `scripts/state-update.py` | before the first file change, after every service, when resuming |
| [verify.md](references/verify.md) + `scripts/verify.sh` | after wiring: the run offer, the exporter log read, the settle, the ONE batched `bluebox ask` |
| [closing-summary.md](references/closing-summary.md) | writing the final message: the fixed shape and the reason set |
| [kubernetes.md](references/kubernetes.md) | only on request: Bluebox monitoring a Kubernetes cluster, never part of a service run |
| [host-prometheus.md](references/host-prometheus.md) | only on request: host metrics, a Prometheus endpoint, log files, datastore receivers - a collector, not SDK wiring |
| [lambda.md](references/lambda.md) | only on request: an AWS Lambda function |

## Inventory, plan, one question, then work

Levels: **1** traces; **2** traces + metrics; **3** traces + metrics + logs, with the
existing logger bridged. Write a level out the first time you name it in a turn, in the
plan table, the question and the "Taking level N" line: `level 3 (traces + metrics +
logs, existing logger bridged)`, `level 2 (traces + metrics)`, `level 1 (traces)`. A bare
number means nothing to the room.

Your first response is the plan the developer approves:

1. **Inventory.** Every service in `src/` (or the equivalent): language, and **telemetry
   today**: `none`; `sdk` (OTel packages in the manifest or a bootstrap file); `agent`
   (a zero-code agent in the image or start command); each with its exporter target,
   `collector:<name>` when `OTEL_EXPORTER_OTLP_ENDPOINT` points at a service of the same
   stack, `direct:<host>` otherwise. A OneAgent SDK is not telemetry: it emits nothing
   without a OneAgent, so it counts as `none (OneAgent SDK present)`, in scope. Read all of
   this from the Dockerfile, the compose/Helm entry, the manifest and the env, not from
   service source. A compose entry that mounts the service's source tree read-only is a
   plan-row fact: new packages go into the image
   ([language-traps.md](references/language-traps.md) § Read-only source). Out of scope,
   one line of reason each:
   browser apps and browser-driving load tools (server-side OTel cannot see their work);
   off-the-shelf images this repo builds no code for (postgres, rabbitmq, nginx: a
   collector concern; an in-stack OpenTelemetry collector is the one exception: it stays
   in scope as the routing row of Hard rule 3); with a compose/Helm stack, services it
   never deploys; images the base image already shows unbuildable on this host. Only what
   the base image tells you up front is a skip; the same blocker met while building is
   `blocked` (Hard rule 12).
   **Runtime probe, in parallel.** With the first inventory read, not after it, start
   the bounded runtime probe of [probes.md](references/probes.md) as its own tool call in
   the same message, and read it when you write the plan: the runtime and its `<compose>`
   command, a runtime the user must start, or none.
2. **Plan, per in-scope service** - one table row, a table even for one service: language,
   recipe (zero-code agent, or SDK when nothing zero-code covers it, written as
   `<package> <version>` with the version resolved under Hard rule 9, e.g.
   `@opentelemetry/auto-instrumentations-node 0.80.0`), and the files that
   will change: the Dockerfile or start command, the deployment entry, for SDK recipes the
   bootstrap file and the request-handling files by name (`handlers*`, `routes*`,
   `controllers*`, the mux registration: span naming and log correlation change call
   sites there; a listed file left untouched is reported "listed, unchanged"), for level 3
   the logging configuration, and for a service whose source is mounted read-only
   (Inventory) the Dockerfile. Name files by convention, not by reading source. A service
   that already exports gets no second SDK or log bridge (Hard rule 3). The table carries
   one environment name for the whole run, the value of `deployment.environment.name`:
   the one `.env.otel.bluebox-template` already sets in `OTEL_RESOURCE_ATTRIBUTES`, else
   the stack's name (`docker-compose`, the Helm release) that you choose here, once. That
   one value goes into every service's `OTEL_RESOURCE_ATTRIBUTES` (Hard rule 5) and into
   every `bluebox ask --env`; a second spelling anywhere (`workshop` in compose,
   `docker-compose` at verify) queries an environment nothing exports to. Under the table: a
   per-runtime legend of what each level yields, and one line "Expected: about L–H min for
   N services; first telemetry shows at the end, verification is batched", L–H as
   [closing-summary.md](references/closing-summary.md) computes it. Then the Runtime line
   from the probe, in the form [probes.md](references/probes.md) gives per state.
   Then the Probe line: each host the reachability line (Workflow step 1) will contact after
   approval, with where it came from.
   Shared files get their own line: compose/Helm and run instructions are edited;
   `.env.otel.bluebox-template` is read, never edited; `.gitignore` gains `.bluebox/`;
   `.bluebox/instrumentation-run.json` records each service as it finishes and
   `.bluebox/instrumentation-run.md` is its readable record; `docs/otel-instrumentation.md`
   is written only when the developer chooses "open a PR" at the end.
   The table plus the shared-files line is the allowlist the developer approves. A file the
   plan did not name gets its own question before you touch it; unattended, leave it and
   mark the service `blocked` (`other: edited since the plan` when it changed under you).
   **Rules for this stack** closes the plan ([rules-table.md](references/rules-table.md)):
   a second table, one row per Hard rule that binds the chosen recipe, each row carrying
   the value you resolved: `rule | binds here | resolved value`. Rows, not prose; a row you
   cannot fill means the plan is not ready to ask.
3. **One question.** Ask scope and depth together: the level (recommend 3 with a
   developer present; level 1 is the fast path) and the scope (default: all in-scope
   server-side services). The plan names the start command, so the run is asked here too:
   "Approve and run" approves the plan and the later start of the app for verification;
   "Approve, I start the app myself" approves the wiring only, and you ask again before
   starting anything. The Runtime line decides which options exist: no usable runtime and
   a daemon to start each narrow them as [probes.md](references/probes.md) states. With
   a question tool (`AskUserQuestion` in Claude Code) ask through it; keep the question
   text sparse: one status line, one compact line per item, the question. The details
   are in the printed plan. The rules table follows the plan
   table in both paths: before the question when one is asked, before the "Taking level
   N" line when not. Without such a tool, ask in plain text and **stop and wait**.
   That pause is the consent gate. A dismissed or canceled question is not an answer:
   stop and say what you would have done. Skip the question only when the user already
   chose, said not to ask, or no interactive user exists (a headless run): then the level
   is the one the request names, logs asked for means 3, otherwise **level 2** (nobody
   consented to application logs leaving the environment), and you print the
   plan table, the rules table, then one line "Taking level N (<what it yields>): <why>" and
   continue.

**Order is fixed: inventory text, plan table, rules table, the question, then the first file
change.**
A file created or edited before the table, or before the question was answered or skipped
for one of the reasons above, is a violation. Do not read service source before the
question either.

## Hard rules

Each rule is stated here once; the reference it names carries the full text and binds
exactly as this line does.

1. **Never handle the ingest token, and never make a tool print it back**: not fetched,
   printed or written anywhere, and validating configuration counts as printing
   ([export-contract.md](references/export-contract.md) § The ingest token).
2. **Config is external.** All transport via standard `OTEL_*` env vars; nothing hardcoded
   in code, no secret committed, env files holding real values git-ignored
   ([export-contract.md](references/export-contract.md) § Config is external).
3. **Zero-code first, and never twice.** Auto-instrumentation before code; a service that
   already exports gets no second SDK or log bridge; an in-stack collector is one plan row
   ([language-traps.md](references/language-traps.md) § Zero-code first).
4. **Logs are additive.** Bridge the logger the service already uses with sink, format,
   timestamps, timezone and levels byte-identical, or the service stays at level 2 and you
   say so ([language-traps.md](references/language-traps.md) § Logs are additive).
5. **Identity attributes.** `vcs.repository.url.full` + `vcs.ref.head.revision` from
   build-time values, `deployment.environment.name` from the plan table, cloud attributes
   where a detector exists ([export-contract.md](references/export-contract.md) § Identity
   attributes).
6. **Self-disabling.** With no `OTEL_EXPORTER_OTLP_ENDPOINT` set, every service behaves
   exactly as before instrumentation ([export-contract.md](references/export-contract.md)).
7. **Protocol is `http/protobuf` and metrics use delta temporality.** In Node the
   `*-otlp-http` packages send JSON and ingest answers 415: `*-otlp-proto` or no exporter
   ([export-contract.md](references/export-contract.md) § Protocol and temporality).
8. **The `Authorization` value comes from the Bluebox Setup page whole, scheme included**:
   `Bearer` for a platform token, `Api-Token` for a classic one, never composed from a
   bare token. Its quotes are consumer-specific
   ([export-contract.md](references/export-contract.md) § The `Authorization` value).
9. **Build-verify every touched service** (compile/test with its normal command) before
   claiming it is wired; fix what you broke, then record the service before the next one.
   Never raise the service's language or runtime version (the `go` directive, `engines`,
   the target framework, the base image tag) to fit an instrumentation release: pin the
   newest instrumentation line that supports the version the repo declares, build in the
   matching image, and say in the plan which versions you pinned and why. Resolve that
   line from the package index at plan time (`npm view <pkg> version`, `pip index versions
   <pkg>`, the Maven or NuGet equivalent) and put the resolved number in the plan table;
   never pin a version from memory. A green build is not the whole check: the exporter
   guard of [language-traps.md](references/language-traps.md) runs before the service is
   recorded; the build caches and the Node recipe are there too.
10. **Narrate progress.** One line at each step boundary: inventory done, per-service
    wired, builds green, app started, verification started and its result. Dead air reads
    as a hang. The backend is Bluebox in every line you write, never the vendor behind
    it, outside product names such as OneAgent.
11. **Finish in one session.** Never end your turn while builds, traffic or verification
    are pending: wait in the foreground with a bounded loop, never through a background
    tool call, and stop only for the asks this skill mandates
    ([session-discipline.md](references/session-discipline.md)).
12. **The host is not yours.** Change only the repository; on the host, build and start
    this repository's own services and stop what you started, nothing else: never kill,
    stop or restart a process this run did not start; a bound port means another port
    or a report, never freeing it ([session-discipline.md](references/session-discipline.md)).

## Workflow

1. Inventory, plan, the rules table, and the one question (above). No request reaches the
   Probe line's hosts before the plan is approved; then run the reachability line of
   [probes.md](references/probes.md) beside step 2's first reads. Unreachable, no retry: a
   registry leaves the run wiring only (`registry_unreachable`), the OTLP endpoint stops it
   after build-verify (`endpoint_unreachable`).
2. **Environment, CLI, template**
   ([export-contract.md](references/export-contract.md) § Endpoint, CLI ladder and the
   template). Look at the environment first, without `env` or `printenv` (Hard rule 1):
   the endpoint alone, the header for presence and scheme only with that section's `case`
   line. An endpoint already exported there IS the endpoint. Without one: `bluebox
   version` compared as semver (below v0.84.0 the CLI is stale and the user's to replace,
   `v0.0.0` exempt), then the run's first CLI call from the repository root,
   `BLUEBOX_JOURNEY_TYPE=instrumentation bluebox otlp-endpoint`: exit 0 printed the endpoint;
   exit 1 the workspace is still provisioning: continue wiring, do not poll; exit 2 no
   observability connection yet: continue wiring and verification is `blocked` on it unless the environment or the template carries an
   endpoint; from a stale CLI an exit 2 stays provisional, never `no_endpoint`. Then the
   token-free `.env.otel.bluebox-template` at the repo root: read, never edited, never
   renamed to a bare `.env.otel`; the ingest token stays out of it, always.
3. Wire the selected services **one at a time**: wire, build-verify (Hard rule 9), record
   ([state-resume.md](references/state-resume.md)), then the next. Update the start
   command and deployment config (compose/Helm/process manager) with non-secret defaults
   only, the token only as a runtime env reference, and the run instructions the repo
   already has. The record write is part of finishing a service, never paperwork for the
   end.
4. **The ingest header is a precondition of the run, not something the run tolerates**
   ([export-contract.md](references/export-contract.md) § Header precondition). Only for
   a run the question granted or the user approves later; a wiring-only run stays
   `user_declined`, and a service step 1 blocked never gets here. Before anything
   verification-related (the start, the traffic, the settle, `bluebox ask`), test the env
   location step 3 named for presence without
   printing the value: that section's per-consumer `grep` for an env file (only the last
   assignment counts; a missing scheme, the wrong quoting for the consumer, a
   placeholder, a `${…}` reference or a CRLF ending all read absent), the step-2 `case`
   for a variable in this shell, the user's answer for their own terminal. Present: step
   5. Absent, user present: **stop** and send that section's one message, never asking
   to see the value and never offering a command that captures it through this shell; on
   done re-test, say what the test wants, ask once more. Absent again counts as skip. On
   skip, or headless: no start against Bluebox, no traffic, no receiver of any kind, no
   `bluebox ask`: the selected services are
   `blocked` (`no_token — …`; with no endpoint at all `no_endpoint — …`) with the
   runnable start command, header as a placeholder, in Next steps. Never start with an
   empty `OTEL_EXPORTER_OTLP_HEADERS` against the Bluebox endpoint: the 401 reads like a
   bad token.
5. With the run granted (at the question, or by the offer in [verify.md](references/verify.md))
   and the header present (step 4: no header, no start): start the app once with its
   normal dev command, or `<compose> up --build` with the compose command the probe found
   (never a literal `docker` the probe did not list), adding for this verification start
   only the standard SDK export knobs,
   `OTEL_METRIC_EXPORT_INTERVAL=10000 OTEL_BSP_SCHEDULE_DELAY=1000 OTEL_BLRP_SCHEDULE_DELAY=1000`
   (milliseconds; the committed run command keeps the SDK defaults), and the runtime's
   diagnostics switch from [language-traps.md](references/language-traps.md). A bound
   default port: start on the next free `PORT` once and say so, never investigate what
   holds it. Drive one request per instrumented service (the repo's load generator or
   reverse-proxy routes when present) and record the window start.

## State and resume

An interrupted run must not start over. Once the question is answered, before any service
file changes, write `.bluebox/instrumentation-run.json` (git-ignored) with the revision,
the level, the scope and one entry per planned service; update one entry the moment its
build-verify passes or it is marked `blocked` or `skipped`, replacing the file rather
than writing over it. `python3 <skill dir>/scripts/state-update.py` is that call. No
secrets in it, ever. The shape, the resume semantics and the readable record
`.bluebox/instrumentation-run.md` are in [state-resume.md](references/state-resume.md).

## Run it, then verify

Nothing can arrive from an app that never ran: if the question did not grant the run,
offer it after wiring and build-verify and ask before starting anything; declined, or no
user and no start, those services are `blocked` with a reason-set token, never
`reporting`. Services step 1 blocked skip it, whatever the question granted. Verification happens EXACTLY once, after all wiring and the traffic window,
only with the ingest header present (step 4), as [verify.md](references/verify.md) says
and `bash <skill dir>/scripts/verify.sh` runs: read the exporter's own log for its failure
lines before you wait (`verify.sh logs …`), fix, restart, read again; settle;
then ONE batched `bluebox ask --env <env>` scoped to the plan table's environment name
(`verify.sh ask …`). Every count you quote names that scope, and a scoped count is never
compared with an unscoped one. Never report `reporting` for a service you saw no signal
from. Before finishing: the secrets scan, and the fresh-window offer after a blocked
window.

## Closing summary (fixed shape)

End the run with the three blocks of [closing-summary.md](references/closing-summary.md),
in this order, built from what the run actually saw: "Time to first telemetry" first,
then **1.** one table, one row per service in the inventory (`service | state | detail`),
**2.** Limitations, **3.** Next steps. `reporting`, `skipped` and `blocked` are the whole
vocabulary, and a `skipped` or `blocked` detail opens with exactly one token of the
reason set that file defines, then `—` and the specifics; a reason outside the set is
written `other: <free text>`. The token is what gets counted, so never invent one. For
deeper query patterns load the **`production-query`** skill.
