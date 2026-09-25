#!/usr/bin/env python3
"""Update one service entry in .bluebox/instrumentation-run.json, atomically.

The record write is part of finishing a service (references/state-resume.md): one call
per service, the moment its build-verify passes or it is marked blocked/skipped. The file
is replaced, never written over, so an interruption leaves the old record or the new one,
never a half-written one.

Usage:
  python3 <skill dir>/scripts/state-update.py --name pricing-service --status wired \
      --file src/pricing-service/main.go --file src/pricing-service/Dockerfile \
      --detail "zero-code Go SDK, logs bridged"
  python3 <skill dir>/scripts/state-update.py --name cart --status blocked --reason build_failed \
      --detail "dotnet restore NU1101 for OpenTelemetry.AutoInstrumentation"

No secrets in the record, ever (Hard rule 1): name a header, never reproduce it. The check
is a tripwire for the shapes the skill's own commands produce: a Dynatrace token prefix, an
Authorization header with its value (`Authorization:`, `Authorization=`, a quoted JSON key, the
scheme right after the name), an Api-Token, Bearer or Basic scheme followed by an opaque value
of 20 or more characters. Naming the header or the scheme without a value passes, and so does
a name or path that only contains a scheme word (`basic-auth-service`, `src/basic/`).
"""
import argparse
import hashlib
import json
import os
import pathlib
import re
import sys

STATUSES = ("planned", "wired", "blocked", "skipped")
# The closing summary's Reason set (references/closing-summary.md): one token per blocked or
# skipped row. The repository's outcome-reasons gate enforces the same set on the closing
# summary and keeps this list and the reference in step.
REASONS = (
    "build_failed",
    "unbuildable_on_host",
    "no_runtime",
    "registry_unreachable",
    "endpoint_unreachable",
    "port_busy",
    "no_endpoint",
    "no_token",
    "egress_blocked",
    "auth_rejected",
    "wire_rejected",
    "endpoint_rejected",
    "signal_unwired",
    "verify_absent",
    "verify_unreadable",
    "pii_withheld",
    "already_instrumented",
    "oneagent_sdk_inactive",
    "version_pinned",
    "out_of_scope",
    "user_declined",
)
# A tripwire for the shapes the skill's own commands produce, not a secret scanner: the rule
# is to name a header, never reproduce it (Hard rule 1). Caught: a Dynatrace token prefix,
# which every Api-Token value carries; `Authorization` followed, after any run of separators,
# by `=`, `:` or a scheme (`Authorization:` in a curl line, `Authorization=` in an OTLP headers
# value, `{"Authorization": ...}`); an Api-Token, Bearer or Basic scheme standing as a word of
# its own followed, after any run of separators, by an opaque value (20+ token characters); an
# OTLP headers assignment. A scheme word joined to a longer name or path by `-`, `/` or a word
# character is no scheme (`basic-auth-service`, `src/basic/handler.go`), and naming the header
# or the scheme without a value ("the Authorization header was rejected", "sent Api-Token on a
# platform token; switch to Bearer") passes.
SECRET = re.compile(
    r"dt0[a-z][0-9]{2}\.|Authorization\W*([=:]|Api-Token|Bearer|Basic)"
    r"|(?<![\w/-])(Api-Token|Bearer|Basic)(?![\w/-])\W*[A-Za-z0-9._~+/=-]{20,}"
    r"|OTEL_EXPORTER_OTLP_HEADERS\s*[=:]",
    re.I,
)


def fail(msg: str) -> "NoReturn":
    print(f"state-update: {msg}", file=sys.stderr)
    sys.exit(1)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--record", default=".bluebox/instrumentation-run.json",
                    help="the run record (default: .bluebox/instrumentation-run.json, from the repository root)")
    ap.add_argument("--name", required=True, help="service name as the plan table names it")
    ap.add_argument("--status", required=True, choices=STATUSES)
    ap.add_argument("--file", action="append", default=[], metavar="PATH",
                    help="repository-relative path the plan row named; repeatable; the sha256 of its current content is recorded")
    ap.add_argument("--reason", default="",
                    help="blocked/skipped only: exactly one token from the closing summary's reason set (e.g. build_failed)")
    ap.add_argument("--detail", default="", help="the concrete detail the closing summary will carry")
    a = ap.parse_args()

    if a.status in ("blocked", "skipped") and not a.reason:
        fail(f"status {a.status} needs --reason (one token from the reason set)")
    if a.status in ("planned", "wired") and a.reason:
        fail(f"status {a.status} takes no --reason")
    if a.reason and a.reason not in REASONS and not re.fullmatch(r"other: \S.*", a.reason):
        fail(f"--reason is one token from the reason set ({', '.join(REASONS)}) or 'other: <free text>'")
    for text in (a.detail, a.reason, a.name):
        if SECRET.search(text):
            fail("a token prefix or an Authorization value would land in the record; name it, never reproduce it")

    rec = pathlib.Path(a.record)
    if not rec.is_file():
        fail(f"{rec} is missing: the record is written once the question is answered, before any service file changes")
    try:
        doc = json.loads(rec.read_text())
    except (OSError, ValueError) as exc:
        fail(f"{rec} does not parse ({exc}); the record is stale, say so and start fresh")
    if not isinstance(doc.get("services"), list):
        fail(f"{rec} carries no services list; the record is stale, say so and start fresh")

    root = pathlib.Path.cwd().resolve()
    files = []
    for f in a.file:
        p = pathlib.PurePosixPath(f)
        if p.is_absolute() or ".." in p.parts:
            fail(f"--file {f}: paths are repository-relative and inside the repository")
        if root not in pathlib.Path(f).resolve().parents:
            fail(f"--file {f}: resolves outside the repository (a symlink out of the checkout is not recorded)")
        try:
            digest = hashlib.sha256(pathlib.Path(f).read_bytes()).hexdigest()
        except OSError as exc:
            fail(f"--file {f}: cannot read ({exc})")
        files.append({"path": str(p), "sha256": digest})

    hit = [svc for svc in doc["services"] if svc.get("name") == a.name]
    if not hit:
        fail(f"{rec} has no service {a.name!r}; the plan table names every service before it is recorded")
    for svc in hit:
        svc["status"], svc["reason"], svc["detail"] = a.status, a.reason, a.detail
        if files or "files" not in svc:
            svc["files"] = files

    tmp = rec.with_name(rec.name + ".new")  # same directory, so the replace is atomic
    tmp.write_text(json.dumps(doc, indent=2) + "\n")
    os.replace(tmp, rec)  # a reader sees the old record or the new one, never a half-written one
    done = sum(1 for svc in doc["services"] if svc.get("status") == "wired")
    print(f"{a.name}: {a.status}{' (' + a.reason + ')' if a.reason else ''}; {done} of {len(doc['services'])} wired")


if __name__ == "__main__":
    main()
