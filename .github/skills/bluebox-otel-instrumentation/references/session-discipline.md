# Session discipline (Hard rules 11 and 12 in full)

The hub states both rules in one line each; this is their full text, with the waits, the
loop and the list of what on the host is never yours.

## Finish in one session (Hard rule 11)

Never end your turn while builds, traffic or verification are pending; poll to completion,
verify, then report. In a non-interactive session, ending early IS the failure. Never wait
through a background tool call. It ends your turn, and unattended there is no next turn:
wait in the foreground with a bounded loop
(`timeout 300 sh -c 'until curl -sf http://localhost:80/ >/dev/null; do sleep 5; done'`)
and raise the tool's own timeout for a long command (`<compose> build`, a health wait, the
batched `bluebox ask`; Claude Code's Bash `timeout`, up to 600000 ms). The only legitimate
stops are the asks this skill mandates: the scope question, the run offer when the plan did
not grant it, the header question of Workflow step 4, and the fresh-window offer after a
blocked window.

## The host is not yours (Hard rule 12)

Change only the repository. On the host, build and start this repository's own services
and stop what you started; never prune, delete, restart or reconfigure anything you did
not create - docker images, containers, volumes, networks (no `prune`, no removal by
filter, listing or age; only your own, by exact name), Kubernetes resources, packages,
daemons, the docker VM. Never kill, stop or restart a process this run did not start. A
port that is already bound is someone else's: pick another port for this run or report the
conflict, and never free it, not by hand and not through a repository recipe that kills
whatever holds the port (`lsof -ti :<port> | xargs kill` and its kin). When the host
blocks progress - disk full, a missing builder, the wrong architecture - say what blocks
and what it would take, mark the affected services `blocked`, and continue with the rest.
`blocked` is for what building revealed; what the Inventory read off the base image stays
`skipped`. A missing or stopped container runtime is the host's state, not a puzzle: the
Inventory probe ([probes.md](probes.md)) is the only lookup you make. Never walk the
filesystem, `/Applications` or `~/.docker` for a binary, never guess socket paths, never
start a daemon or machine, never install one. Name the command the user runs (`podman
machine start`, open Docker Desktop, install one) and mark the services `blocked`
(`no_runtime — …`).
