# Probes

Two bounded, read-only probes, each its own tool call with the tool's timeout parameter at
30 s (Claude Code Bash: `timeout: 30000`; the default is 120 s). The runtime probe runs
beside the first inventory read and is read when the plan is written; the reachability
line runs only once the plan is approved (Workflow step 1). Neither writes anything, so
the hub's order rule is untouched.

## Runtime probe

**Runtime probe, in parallel.** With the first inventory read, not after it, start one
bounded probe for the container runtime the stack would run under. This must not slow
the plan. Read its result when you write the plan:

```bash
/bin/sh -c 'set -f; unset -f podman docker nerdctl command cd pwd echo test; r=$(cd -P . && pwd); while test "$r" != / && test ! -e "$r/.git"; do r=${r%/*}; test -z "$r" && r=/; done; test -e "$r/.git" || r=$(cd -P . && pwd); p=; IFS=:; for d in $PATH; do case $d in /*) ;; *) continue;; esac; pd=$(cd -P "$d" 2>/dev/null && pwd) || continue; in=0; for x in "$d" "$pd"; do while test -n "$x"; do test "$x" -ef "$r" && in=1; if test "$x" = /; then x=; else x=${x%/*}; test -z "$x" && x=/; fi; done; done; test $in = 0 && p="$p${p:+:}$d"; done; unset IFS; PATH=${p:-/nonexistent}; for rt in podman docker nerdctl; do b=$(command -v "$rt") || continue; case $b in /*) ;; *) continue;; esac; c=none; "$b" compose version >/dev/null 2>&1 && c="$rt compose"; if test "$c" = none; then bc=$(command -v "$rt-compose") && case $bc in /*) "$bc" version >/dev/null 2>&1 && c="$rt-compose";; esac; fi; d=down; "$b" version --format "{{.Server.Version}}" >/dev/null 2>&1 && d=up; echo "$rt: daemon=$d compose=$c"; done; echo probe-done'
```

Run it as its own tool call in the same message as the first inventory reads (that is the
parallelism), passing the tool's timeout parameter as 30 s (Claude Code Bash: `timeout:
30000`; the default is 120 s), and read its output when you write the plan. `command -v`
and version calls only: never search the filesystem for a binary, never start a daemon or
machine, never install anything (Hard rule 12). The probe disables pathname expansion,
forgets the shell functions named like a runtime or like a regular builtin it calls
(`command`, `cd`, `pwd`, `echo`, `test`), calls no other regular builtin (`[`, `:` and
`break` are gone; `unset -f` cannot drop the first two) and beyond keywords uses only the
special builtins `set`, `unset` and `continue`, which a POSIX `sh` resolves before any
function, and runs only a runtime that `command -v` resolves to an absolute path (an
exported `podman(){ … }`, `podman-compose(){ … }` or `cd(){ … }` travels through the
environment into `/bin/sh`), drops relative entries and entries inside the repository
(any ancestor of the entry, as written or resolved, is the root: the nearest `.git` at or
above the cwd, else the cwd; from a cwd that is not inside a checkout a dotfiles
repository in `$HOME` would be that root, and the skill runs inside the checkout it
instruments) from `PATH` and runs under `/bin/sh` by path, so this probe never runs a
binary the repository plants on `PATH` (`direnv`, a `node_modules/.bin`), and a harness
that masks a runtime from `PATH` is respected. The filter is directory-scoped and trusts
any `PATH` directory outside the checkout as the host's own, so a symlink placed in one
that points back into the checkout still runs: planting it needs write access outside the
repository, which defeats any `PATH` filter anyway. It binds this probe alone: Hard rule
9's version lookups are pre-consent reads under their own rules, and the reachability line
has its own (Workflow step 1). Nothing is written, so the hub's order rule is untouched.
Read the output as four states: the first line with `daemon=up` and a compose command is
**the runtime** (the loop lists podman first: Bluebox prefers podman wherever both are
installed), and its `compose=` value is `<compose>` everywhere this skill says so
(`docker compose`, `podman compose`, `podman-compose`, `nerdctl compose`);
`daemon=up compose=none` on every line is a runtime without compose - for a compose stack
that is **no usable runtime**, say which plugin is missing; `daemon=down` on every line is
**a runtime the user must start** (name the first line's runtime, podman when both are
installed); no line at all is **no runtime**. A tool result reporting the timeout (partial
output, no `probe-done` line) is a hung daemon: report that runtime as unresponsive and
re-run the loop once without it. A stack that needs no runtime (a plain `make run`, `npm
start`) reads the probe as informational.

**The plan's Runtime line, and the options it leaves.** The plan carries one line from the
probe: "Runtime: podman (daemon up, `podman compose`)", or "Runtime: <rt> found, daemon
down - start it (<the detected runtime's own start step: `podman machine start`, Docker
Desktop or `dockerd`, nerdctl's containerd VM>) before the run", or "Runtime: none found -
this stack cannot be built or started on this host; wiring only". That line decides which
options the one question offers: with no usable runtime for a containerized stack, do not
offer "Approve and run" - the question offers the wiring only, and the run and the
verification are not proposed at all, not now and not after wiring (those services close
`blocked`, `no_runtime — …`, with the commands in Next steps); with a runtime the user must
start (daemon down), offer "Approve, I start the app myself" only, and re-run the probe
before any start; a package index Hard rule 9's lookup could not reach leaves the wiring
only (below).

**The plan's Probe line.** Then the Probe line: each host the reachability line (Workflow
step 1) will contact after approval, with where it came from, as in "Probe after approval:
registry-1.docker.io; ghcr.io (compose); 127.0.0.1:4318 (OTLP endpoint, template)". The
OTLP endpoint is the shell's `OTEL_EXPORTER_OTLP_ENDPOINT` when it is exported and not
empty (read it with Workflow step 2's `printf`), else the template's.

## Reachability probe

Its two reason tokens, `registry_unreachable` and `endpoint_unreachable`, are defined in
[closing-summary.md](closing-summary.md).

**Reachability, after approval.** A runtime that is there can still reach nothing:
behind a corporate proxy or a restricted registry, the first image pull or package
install is where a run would otherwise thrash. So once the plan is approved (an "Approve"
answer to the question, or the question skipped with the "Taking level N" line), run the
read-only reachability line in your next message, as its own tool call beside step 2's
first reads, with the runtime probe's 30 s timeout. Never before, and no other request to
those hosts either: the line reaches hosts the repository names (the template's endpoint, a
registry in a compose file), a cloned repository can aim them at loopback or a metadata
address, and the plan's Probe line is where the developer sees each host first. A template
holding `OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4318` puts `127.0.0.1:4318` on that
line and gets no request until the plan is approved (none while the question is open, and
none at all when it is dismissed, canceled or answered with a rescope), then one bare HEAD
to `http://127.0.0.1:4318/v1/traces`:

```bash
sh -c 'command -v curl >/dev/null 2>&1 || { echo "curl: absent"; echo probe-done; exit 0; }; p() { c=$(curl -q -sI -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 -- "$2"); case $c in 401|403|405|415) s=auth-gated;; 407|5??|000|"") s=unreachable;; [234]??) s=reachable;; *) s=unreachable;; esac; echo "$1: $s http=$c"; }; p registry https://registry-1.docker.io/v2/; ep=${OTEL_EXPORTER_OTLP_ENDPOINT:-$(sed -n "/^OTEL_EXPORTER_OTLP_ENDPOINT=/{s/^[^=]*=//;s/\"//g;p;}" .env.otel.bluebox-template 2>/dev/null | head -1)}; case $ep in http://*|https://*) a=${ep#*://}; case ${a%%[/?#]*} in *@*) echo "otlp: invalid";; *) p otlp "${ep%/}/v1/traces";; esac;; "") echo "otlp: unset";; *) echo "otlp: invalid";; esac; echo probe-done'
```

`curl -q -I` with the body to `/dev/null`: `-q` first, so the host's `.curlrc` cannot add
a header, a credential or a proxy of its own; no method, no data and **no header, ever** - the
OTLP check goes out bare, and a 4xx from both targets is the expected answer (Hard rule
1). The endpoint is `OTEL_EXPORTER_OTLP_ENDPOINT` when the shell already exports it, else
the endpoint line of the token-free template in the repo root, where the line runs. Three states per target: `reachable`
(2xx, 3xx, or any other 4xx: the target answered, a wrong path is step 2's business, not
the network's) and `auth-gated` (the target itself answered 401, 403, 405 or 415 - the
registry's 401 and the endpoint's 401 or 405 with no header are the normal reads) both
mean the host is reached; `unreachable` (`http=000`: DNS, TCP, TLS or the proxy failed
inside 10 s; 407: the proxy wants credentials; 5xx or no code: the proxy or the target
answered for a host it could not serve) means it is not. Anything else is `unreachable`,
never `reachable` by default. `otlp: unset` is no state: nothing to probe yet, Workflow
step 2 resolves the endpoint (`no_endpoint` is its token); `otlp: invalid` is a template
value without an `http(s)://` scheme, or one with userinfo in its authority (`user:secret@host`,
which curl would send as a Basic header) - the line probes only a bare URL, never
passes the value as an option (`--`), and step 2 sorts the template out; `curl: absent` is no read
at all - say so in one line and go on. A tool result without `probe-done` is a
hung proxy: the target whose line is missing reads `unreachable`. A compose file naming
a registry other than docker.io (`ghcr.io`, `quay.io`, a company mirror) gets the same
call once more in that message, with one `p registry "https://<host>/v2/"` added per
host, and only for a bare host name with an optional port (letters, digits, `.` and `-`,
then `:` and digits): anything else is not probed, and the Probe line says so. Each target
owns 10 s of the 30 s tool timeout, so a third host goes on a line of its own. The package
index needs no third target: Hard rule 9's version lookup at plan
time is its probe, and a lookup that cannot connect (ENOTFOUND, ECONNREFUSED,
ETIMEDOUT, a proxy 407 - not an unknown package) reads `unreachable` too; that read comes
before the question, so the plan's Runtime line names it and the question offers the
wiring only.
On `unreachable`: no proxy hunting, no mirror guessing, no `HTTPS_PROXY` edits, no retry
(Hard rule 12). Name the target and its `http=000` in one line. Registry unreachable
(container registry or package index): the run is wiring only, and every service in it
closes `blocked` (`registry_unreachable — …`). A service whose build pulls or installs
from it lists its build command in Next steps; the rest, wired and build-verified, list
their start and verification commands there. OTLP endpoint unreachable: wire and build-verify,
then neither start nor verify, and offer neither later. Those services close `blocked`
(`endpoint_unreachable — …`) with the start and verification commands in Next steps.
Re-run the line exactly once when the first build fails on a connection (the error names
a host, a proxy or a timeout, not a package): a target now `unreachable` blocks that
service on the same token and ends the retries; still reachable, the failure is
`build_failed`. A second build failure of the same kind is not a second probe.
