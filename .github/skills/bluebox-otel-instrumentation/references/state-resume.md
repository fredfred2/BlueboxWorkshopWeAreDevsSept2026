# State and resume

An interrupted run must not start over. Once the question is answered, before any service
file changes, write `.bluebox/instrumentation-run.json` (`.bluebox/` git-ignored): the
revision (`git rev-parse HEAD`), the level, the scope, and one entry per planned service -
`status` (`planned`, `wired`, `blocked`, `skipped`), the files its plan row named as
repository-relative paths with the sha256 of their content after your edit, the `reason`
token of a `blocked` or `skipped` entry (the closing summary's reason set; empty
otherwise) and the detail the closing summary will carry:

```json
{"revision": "<git rev-parse HEAD>", "level": 3, "scope": "all",
 "services": [{"name": "pricing-service", "status": "planned",
               "files": [{"path": "src/pricing-service/main.go", "sha256": "..."}],
               "reason": "", "detail": ""}]}
```

Update one entry the moment that service's build-verify passes or it is marked `blocked`,
one call per service, and replace the file rather than writing over it. An interruption
inside an in-place write leaves the only record unreadable. `scripts/state-update.py` in
this skill's directory is that call, run from the repository root:

```bash
python3 <skill dir>/scripts/state-update.py --name pricing-service --status wired \
    --file src/pricing-service/main.go --file src/pricing-service/Dockerfile \
    --detail "zero-code Go SDK, logs bridged"
python3 <skill dir>/scripts/state-update.py --name cart --status blocked \
    --reason build_failed --detail "dotnet restore NU1101 for OpenTelemetry.AutoInstrumentation"
```

It records the sha256 of each named file as it stands after your edit, writes the new
record to a temp file in the same directory and renames it over the old one (a reader sees
the old record or the new one, never a half-written one), takes `--reason` only for a
`blocked` or `skipped` entry and only as one token from the reason set (or `other: <free
text>`), and refuses a name, reason or detail that carries a token prefix or an
`Authorization` value.

No secrets in it, ever. On start, read the file only if it parses, carries those fields and
every path is relative and inside the repository; anything else is stale. Say so and start
fresh. Same revision, same scope and level, a service still `planned`: that is a resume.
Say "resuming: N of M wired", print the plan table with each service's recorded status (a
`blocked`/`skipped` row as `reason — detail`), take the recorded level as the answer, and
continue from the first service not `wired` or `blocked`. Per named file of that service:
content matching the recorded hash is your finished edit; matching the revision is
untouched, wire it; anything else is the developer's own work. Ask before touching it
(unattended: leave it, mark the service `blocked` with `other: edited since the plan`).
Nothing left `planned` is a finished run; a different scope, level or revision is not a
resume either: say what it records and ask whether to start over (unattended: start over
and say why). The developer removes the file when done; the closing summary names it under
next steps when anything is not `wired`.

## The readable record

Next to the JSON, keep `.bluebox/instrumentation-run.md` for the
developer: header (repository, revision, started, a five-entry progress line Scan · Plan ·
Instrument · Verify · Handover, status); a decisions table (when, step, question, choice,
by whom - rescopes and retests included); then one section per step carrying the same
tables and lines as your step reports (inventory with telemetry today, approved plan and
prerequisites, files changed, verification table with window and attempts, handover with
run and re-verify commands, limitations, next steps), `_pending_` until reached - never
raw command output, never a header value, a token, a credential-bearing URL or customer
data (Hard rule 1 applies to this file as to your own output). Rewrite it whole at every
step boundary, temp file and rename, the last time after the final decision; plain
markdown. On "open a PR", copy it to `docs/otel-instrumentation.md` under the same
rule, commit it with the code, and use its handover section as the PR body.
