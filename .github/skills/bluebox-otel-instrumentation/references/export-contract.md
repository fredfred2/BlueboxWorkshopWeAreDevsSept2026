# Bluebox export contract

The transport facts every recipe binds to. Each fact lives here once; the hub's Hard
rules point at it. Read this before the plan table (Hard rules 1, 2, 5–8 resolve here) and
again at Workflow steps 2 and 4.

## The ingest token (Hard rule 1)

**Never handle the ingest token, and never make a tool print it back.** Do not fetch,
print, or write it anywhere; the app reads it from an env var or secret the user supplies
(Bluebox Setup page). Validating configuration counts as printing: `<compose> config`,
`env`, `printenv`, `cat` on a file that carries the token all put it in your recorded
output. Validate with `<compose> config --quiet` (or `helm template` on values that hold
no token) and filter header and token lines out of anything you must read. If a value
does reach your output, say so and tell the user to rotate it on the Bluebox Setup page
(`<bluebox-host>/setup`; `<bluebox-host>` is the Bluebox URL the user works in, where the
token came from). Ask when nothing in the repo or the request names it; never guess a
host. Hard rule 1 applies to `.bluebox/instrumentation-run.md` and to your final message
as to any other output.

## Config is external (Hard rule 2)

All transport via standard `OTEL_*` env vars - endpoint, headers, protocol,
`OTEL_SERVICE_NAME`, `OTEL_RESOURCE_ATTRIBUTES`. Never hardcode endpoints, tokens or
service names in code; never commit secrets; confirm env files holding real values are
git-ignored. Update the start command and deployment config (compose/Helm/process
manager) with non-secret defaults only, the token only as a runtime env reference, and
the run instructions the repo already has.

## Self-disabling (Hard rule 6)

With no `OTEL_EXPORTER_OTLP_ENDPOINT` set, every service behaves exactly as before
instrumentation.

## Protocol and temporality (Hard rule 7)

**Protocol is `http/protobuf`** (`OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf`); ingest
rejects other OTLP transports. **Metrics use delta temporality**
(`OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=delta`); ingest rejects cumulative
series. When code constructs an exporter itself the SDK picks the wire format from the
package, not the variable: in Node the `@opentelemetry/exporter-*-otlp-http` packages
send JSON and ingest answers **415** with nothing arriving. The Node recipe in
[language-traps.md](language-traps.md) names the `*-otlp-proto` packages, and the
exporter guard there fails the service while a JSON one is still installed.

**A collector between the SDK and Bluebox** carries the same contract: a Bluebox
`otlphttp` exporter (http/protobuf, the token from the environment only) on its existing
pipelines, with the `cumulativetodelta` processor on the metrics pipeline (ingest rejects
cumulative series; [host-prometheus.md](host-prometheus.md) shows the processor), through
the repo's extras/override config when it has one. Gauges are unaffected either way;
logs (`filelog`) need no conversion. Dual export to an old backend and Bluebox is a
collector, not two exporters in the SDK.

## Identity attributes (Hard rule 5)

`vcs.repository.url.full` + `vcs.ref.head.revision` from build-time values (build-arg ->
env; drop the pair when empty, never emit empties), `deployment.environment.name` (the
plan table's one environment name), plus cloud resource attributes where a detector
exists. This is what maps telemetry back to code and environment. The environment name is
one value for the whole run: the one `.env.otel.bluebox-template` already sets in
`OTEL_RESOURCE_ATTRIBUTES`, else the stack's name (`docker-compose`, the Helm release)
chosen once in the plan table; it goes into every service's `OTEL_RESOURCE_ATTRIBUTES`
and into every `bluebox ask --env`. A second spelling anywhere (`workshop` in compose,
`docker-compose` at verify) queries an environment nothing exports to.

## The `Authorization` value (Hard rule 8)

**The `Authorization` value is whole, scheme included, and you never compose it.** The
scheme depends on the workspace's ingest-token kind (`Bearer` for a platform token
`dt0s16…`, which is what Bluebox mints; `Api-Token` for a classic `dt0c01…`), and a
guessed scheme yields a 401 that reads like a bad token. The value reaches the process
through the env location the plan names, by one of two supply paths, and the plan says
which:

- **Pasted whole.** Copy token on the Bluebox Setup page gives the whole line,
  `OTEL_EXPORTER_OTLP_HEADERS="Authorization=<scheme> <token>"`, double-quoted; the user
  pastes it into the env location the plan names (Workflow step 4 gives the wording).
- **The token-file convention.** Where the repo's own dev notes route the token through
  `~/.bluebox/ingest-token.env` - outside the repository, mode 600, holding
  `BLUEBOX_INGEST_TOKEN=<token>` - the repo's start command derives the header at start
  from the token's prefix, with the mapping above fixed in the command (`dt0s16` gives
  `Bearer`, `dt0c01` gives `Api-Token`, any other prefix refuses to start) and exports
  `OTEL_EXPORTER_OTLP_HEADERS` to the process only. The file is the user's: you never
  create, read, print or `cat` it, and the start command never echoes what it derived.
  The precondition test for this path is presence-only:
  `grep -Eq '^BLUEBOX_INGEST_TOKEN=(dt0s16|dt0c01)\.[A-Za-z0-9._-]+[[:blank:]]*$' ~/.bluebox/ingest-token.env`
  (exit 0 present; the token-file line is `no_token — ~/.bluebox/ingest-token.env has no
  BLUEBOX_INGEST_TOKEN value` when absent). The `Bearer`/`Api-Token` choice is never
  yours at wiring time and never a pin from memory.

The value contains a space, so the quotes are consumer-specific: keep them in a shell or
a `.env` the shell sources, either way in a Compose `env_file` (it strips either quote),
**drop them** in a Docker `--env-file` (it passes quotes into the header), and on gcloud
use `--set-env-vars` with `^;^` delimiter syntax or a Secret Manager reference, never
`--env-vars-file`.

## Endpoint, CLI ladder and the template (Workflow step 2)

Look at the environment first, without `env` or `printenv` (Hard rule 1): print the
endpoint alone with `printf '%s\n' "$OTEL_EXPORTER_OTLP_ENDPOINT"` and test the header for
presence and scheme only (Hard rule 8), always exiting 0 because absent is a supported
state - the same absent set as the step-4 file test: a `<placeholder>`, a `${…}`
reference, a quote, any whitespace after the scheme's one space (a trailing newline
included), no scheme, `Bearer` on a classic `dt0c01…` token, or `Api-Token` on a platform
token:
`case "$OTEL_EXPORTER_OTLP_HEADERS" in *"<"*|*"$"*|*\"*|*"'"*|"Authorization=Bearer dt0c01."*|"Authorization=Bearer "*[[:space:]]*|"Authorization=Api-Token "*[[:space:]]*) echo "headers: absent";; "Authorization=Bearer "?*|"Authorization=Api-Token dt0c01."?*) echo "headers: set";; *) echo "headers: absent";; esac`.
An endpoint already exported there (the workshop and CI path) IS the endpoint; use it
as-is and read the CLI call below as informational only.

Without one, `bluebox version` next, compared as semver (v0.100.0 is above v0.84.0):
below v0.84.0 the CLI is stale. Those builds exit 2 on a workspace that is already
connected (#13763), and `v0.0.0` is a dev build, exempt. A stale CLI is the user's to
replace, not yours (Hard rule 12; `bluebox update` also exits 0 without replacing a
package-manager install): say in one line that it is behind and that `bluebox update`
fixes it, then continue with the binary you have.

Then open the run's journey with its first CLI call, from the repository root:
`BLUEBOX_JOURNEY_TYPE=instrumentation bluebox otlp-endpoint`. The CLI mints one id for
this run, and every later `bluebox` call from this directory carries it; the variable
goes on that one call only. Exit 0 printed the endpoint; exit 1 = the workspace is still
provisioning - tell the user and continue wiring, do not poll; exit 2 = no observability
connection yet - tell the user to connect one on the Setup page, continue wiring (the
config is external) and treat verification as `blocked` on it unless an endpoint is
already in the environment or the template. With an endpoint already exported, none of
that ladder applies: the call was informational, nothing is blocked and no reason is
recorded from it. From a stale CLI, or when stderr says the CLI "is behind … run `bluebox
update`", exit 2 is not yet that verdict: tell the user that `bluebox update` and a second
`bluebox otlp-endpoint` settle it, and that the Setup page is where a missing connection
gets made if the updated CLI still exits 2. An unconfirmed exit 2 is never recorded as
`no_endpoint`. The detail stays provisional until a current CLI answers (`other:
otlp-endpoint exit 2 from bluebox v0.75.0, below v0.84.0, unconfirmed`) and becomes
`no_endpoint` only when one does.

Then use the token-free `.env.otel.bluebox-template` at the repo root. `bluebox setup
local-repos` generates it with the endpoint pre-filled (missing? put the endpoint the
first call printed in the deployment entry; do not hand-write the template). Never rename
it or write a bare `.env.otel` (CLI tests reject that path). The ingest token stays out of
it, always; it is read, never edited.

## Header precondition (Workflow step 4)

The ingest header is a precondition of the run, not something the run tolerates. This
step is for a run the question granted, or one the user approves later
([verify.md](verify.md)); a wiring-only run never reaches it and stays `user_declined`, and
neither does a service Workflow step 1's probe closed `registry_unreachable` or
`endpoint_unreachable`, whatever the question granted.
Before anything verification-related (the start, the traffic, the settle, `bluebox ask`),
test the env location you named in Workflow step 3 for presence without printing the
value (Hard rule 1). Env file:
`V="Authorization=(Bearer [^<\"'[:space:]$]+|Api-Token dt0c01\.[^<\"'[:space:]$]+)"; A="^[[:space:]]*(export[[:space:]]+)?OTEL_EXPORTER_OTLP_HEADERS="; grep -Eq "$A" "<file>" && grep -E "$A" "<file>" | tail -n 1 | grep -Ev "Bearer[[:space:]]+dt0c01\." | grep -Eq "^<line>[[:blank:]]*\$"`
with `<line>` per what reads `<file>` (Hard rule 8): `$A(\"$V\"|'$V')` when a shell
sources it (the space in the value needs the quotes), `$A($V|\"$V\"|'$V')` for a Compose
`env_file`, `[[:space:]]*OTEL_EXPORTER_OTLP_HEADERS=${V}` for a Docker `--env-file` (no
quotes, no `export`: it refuses both; indentation every reader drops; the braces keep zsh
from reading `$V[` as a subscript). Only the last assignment counts, as every reader
resolves it. So a missing scheme, `Bearer` on a classic `dt0c01…` token, the quoting or
`export` the consumer cannot take, a quote left open, a `${…}` reference, a
`<placeholder>`, a CRLF line ending (the CR would ride into the header), and a good line
with the template's placeholder still under it all read absent. Exit 2 is neither:
`<file>` is missing or unreadable, a path mistake. Fix the path from step 3 (or write the
token-free template there) and test again. Token file (the convention above): its
presence-only grep. Shell variable in this shell: the step-2 `case`. Shell variable in the
user's own terminal ("Approve, I start the app myself"): you cannot test it; ask whether
`OTEL_EXPORTER_OTLP_HEADERS` is exported in the terminal that runs the start command and
take the answer.

Present: Workflow step 5. Absent, user present: **stop** and give the instructions,
nothing else - one message of this shape, `<file>` filled in (for a shell variable:
`export` in that terminal instead of the file line): "Verification needs the ingest
header and `<file>` has none. On the Bluebox Setup page click Reveal token, then Copy
token: that is the whole `OTEL_EXPORTER_OTLP_HEADERS="…"` line, scheme included. Open
`<file>` in your own editor and paste it in as its own line, quotes and all - over the
`OTEL_EXPORTER_OTLP_HEADERS=` line if `<file>` has one, else as a new line; into `<file>`
only, never into `.env.otel.bluebox-template`, which is committed (a Docker `--env-file`
is the exception on quotes: drop the two, it passes them into the header). Then save and
say done, or skip." Never ask to see it, and never offer a command that captures it
through this shell - no `read`, no `echo`, no heredoc: a paste into the transcript burns
the token. Then **stop and wait** under the same consent gate as the plan question: a
dismissed or canceled question is not an answer, and "Approve and run" granted the
start, not a start without the header.

On done, re-test; still absent, say what the test wants - the line starts with
`OTEL_EXPORTER_OTLP_HEADERS=` (`export` in front is fine where a shell reads the file),
the value starts with `Authorization=` (first, if it carries other headers), then the
scheme (`Bearer `, or `Api-Token ` for a `dt0c01…` token) and one space, the quotes kept
or dropped as Hard rule 8 says for `<file>`, no `<placeholder>`, no `${…}` reference, the
last uncommented `OTEL_EXPORTER_OTLP_HEADERS=` line in the file (a `#` line does not
count; remove any earlier real one), nothing after the value on that line (a trailing `#`
comment counts), saved with LF line endings - and ask once more; absent again counts as
skip.

On skip, or with no user present (headless): no start against Bluebox, no traffic, no
receiver of any kind, no `bluebox ask`. The selected services are `blocked` (`no_token —
<file> has no Authorization value`; shell variable: `no_token — OTEL_EXPORTER_OTLP_HEADERS
not exported`), the runnable start command with the header as a placeholder goes in next
steps, and you finish as [verify.md](verify.md) says: the secrets scan first, then the
closing summary. No endpoint at all (step 2 exit 2 and none in the environment or the
template) stops the same way, `blocked` (`no_endpoint — …`). Never start with an empty
`OTEL_EXPORTER_OTLP_HEADERS` against the Bluebox endpoint: the 401 in the container logs
reads like a bad token.
