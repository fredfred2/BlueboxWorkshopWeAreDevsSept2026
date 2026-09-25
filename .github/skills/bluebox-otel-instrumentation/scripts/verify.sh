#!/bin/sh
# verify.sh — the two commands of references/verify.md, with their guards built in.
#
#   bash <skill dir>/scripts/verify.sh logs --lang node|java|python|dotnet|go --service <name> \
#             (--compose "<compose>" | --logs-cmd "<command>") [--since 2m]
#       Reads the exporter's own log for the failure lines of that runtime, never the whole
#       log: greps the status lines, withholds a failure line that mentions a header (it is
#       counted, and a count means the transport is not confirmed), cuts query strings and
#       user-info out of URLs, masks a Dynatrace token and an Authorization, Api-Token,
#       Bearer, Basic or OTLP headers value wherever it stands, in the log and in the echoed
#       command alike (Hard rule 1). Runs the log command exactly once: a non-zero exit is a
#       run problem (wrong service name, container gone, no log file yet), never a clean
#       transport — exit 2, nothing shown. --compose is the compose
#       command the runtime probe found (`podman compose`, `docker compose`, ...);
#       --logs-cmd replaces the compose log command for a stack that is not compose
#       (`kubectl logs <pod>`, `journalctl -u <unit>`).
#
#   bash <skill dir>/scripts/verify.sh ask --env <env> --window "<T1>..<now>" --services "<a>, <b>" \
#             --signals "spans, logs, and metrics" [--print]
#       Runs the ONE batched check, verbatim from references/verify.md, scoped to the plan
#       table's environment name. --print shows the command instead of running it.
#
# Exit: 0 read or ask done (the output is the evidence); 1 bad arguments; 2 the log command
# itself failed. Raise the tool's own timeout for the ask (Hard rule 11).
set -u
set -f

usage() { sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
die() { printf 'verify.sh: %s\n' "$*" >&2; exit 1; }

mode=${1:-}; [ -n "$mode" ] && shift
lang= service= compose= logs_cmd= since=2m env= window= services= signals= print=0
# bash fails a `shift 2` short of a value without shifting: a value flag given last would loop forever.
need_value() { [ "$1" -gt 1 ] || die "$2 needs a value"; }
while [ $# -gt 0 ]; do
  case $1 in
    --lang) need_value $# "$1"; lang=$2; shift 2;;
    --service) need_value $# "$1"; service=$2; shift 2;;
    --compose) need_value $# "$1"; compose=$2; shift 2;;
    --logs-cmd) need_value $# "$1"; logs_cmd=$2; shift 2;;
    --since) need_value $# "$1"; since=$2; shift 2;;
    --env) need_value $# "$1"; env=$2; shift 2;;
    --window) need_value $# "$1"; window=$2; shift 2;;
    --services) need_value $# "$1"; services=$2; shift 2;;
    --signals) need_value $# "$1"; signals=$2; shift 2;;
    --print) print=1; shift;;
    -h|--help) usage;;
    *) die "unknown argument: $1";;
  esac
done

# Only the characters a service, environment or window can carry: anything else is not run.
safe() { case $2 in ''|*[!A-Za-z0-9._:+/@-]*) die "$1 must match [A-Za-z0-9._:+/@-]+ and not be empty";; esac; }
# Single-quote a value for a printed command, so a quote in a service name cannot become shell syntax.
shq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
# The one filter every log-derived line and the echoed log command pass through. It masks what
# state-update.py refuses, and its output passes that check again: a Dynatrace token, a query
# string, URL userinfo, an Authorization value, an Api-Token, Bearer or Basic value, an OTLP
# headers assignment; an Authorization value takes the rest of its line, a quoted headers value
# goes whole to its closing quote. The
# placeholder sits directly on the name so no separator survives.
mask() {
  sed -E -e 's/\?[^[:space:]]*//g' -e 's#://[^/[:space:]]*@#://#g' \
    -e 's/dt0[a-z][0-9]{2}\.[A-Za-z0-9._-]*/<token>/Ig' \
    -e 's/authorization[^[:alnum:]]*([=:]|api-token|bearer|basic).*/Authorization<token>/I' \
    -e 's/(api-token)[[:space:]:=]+[^[:space:]]+/\1<token>/Ig' \
    -e 's#(api-token|bearer|basic)[^[:alnum:]]*[A-Za-z0-9._~+/=-]{20,}#\1<token>#Ig' \
    -e "s/OTEL_EXPORTER_OTLP_HEADERS[[:space:]]*[=:][[:space:]]*(\"([^\"\\\\]|\\\\.)*\"?|'[^']*'?|[^[:space:]]*)/OTEL_EXPORTER_OTLP_HEADERS<token>/Ig"
}

case $mode in
logs)
  safe --service "$service"
  case $since in ''|*[!0-9smh]*) die "--since is a duration like 2m";; esac
  case $lang in
    node)   greps="-e 'export failed' -e 'export request'";;
    java)   greps="-e 'Failed to export'";;
    python) greps="-e 'Failed to export' -e 'Transient error'";;
    dotnet) greps="-e 'Exporter failed' -e 'status code'";;
    go)     greps="-e 'failed to send'";;
    *) die "--lang is one of node, java, python, dotnet, go";;
  esac
  if [ -n "$logs_cmd" ]; then
    read_cmd=$logs_cmd
  elif [ -n "$compose" ]; then
    case $compose in *[!A-Za-z0-9._\ /-]*) die "--compose is the probe's compose command, e.g. 'podman compose'";; esac
    if [ "$lang" = dotnet ]; then
      # .NET writes the exporter's failures to its log file, not to stdout (OTEL_DOTNET_AUTO_LOG_DIRECTORY).
      read_cmd="$compose exec $service sh -c 'cat /var/log/opentelemetry/dotnet/*'"
    else
      read_cmd="$compose logs --since $since $service"
    fi
  else
    die "logs needs --compose \"<compose>\" or --logs-cmd \"<command>\""
  fi
  # An empty read is evidence only when the log command itself succeeded. One run: the raw
  # text stays in this variable and leaves it only through the filters below.
  raw=$(sh -c "$read_cmd" 2>&1); rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'log read failed (exit %s) for: %s\nfix the run (service name, container, log file), this is not a clean transport\n' "$rc" "$(printf '%s' "$read_cmd" | mask)"
    exit 2
  fi
  hits=$(printf '%s\n' "$raw" | eval "grep -ai $greps")
  # A failure line naming a header may carry its value: counted, never shown, never a clean read.
  held=$(printf '%s\n' "$hits" | grep -ciE 'authorization|header')
  out=$(printf '%s\n' "$hits" | grep -viE 'authorization|header' | mask)
  if [ -n "$out" ]; then
    printf '%s\n' "$out"
  fi
  if [ "$held" -gt 0 ]; then
    printf '%s failure line(s) for %s (%s) mention a header and are withheld: the transport is NOT confirmed; re-test the ingest header (Workflow step 4) before reading again\n' "$held" "$service" "$lang"
  elif [ -z "$out" ]; then
    printf 'no failure line for %s (%s) in the last %s: the transport is right for what the code exports\n' "$service" "$lang" "$since"
  fi
  ;;
ask)
  safe --env "$env"
  [ -n "$window" ] || die "--window is the traffic window, <T1>..<now>"
  [ -n "$services" ] || die "--services lists the selected services"
  [ -n "$signals" ] || die "--signals names the signals the user selected, e.g. 'spans, logs, and metrics'"
  prompt="For the window $window: which of these services have $signals arriving — $services? Count by OTLP service.name, not by entity. For metrics: FIRST list every metric key that carries that service.name in the window (the catalog for that service - do not test guessed key names or prefixes), then judge from that list; any key the app exported counts - request, client-side (http.client.*), runtime, JVM - but list dt.* and other entity-derived keys separately and do not count them: dt.service.request.count/failure_count/response_time are derived from spans and exist for every service with inbound request spans. List per-service signals, the metric keys seen, and the values of vcs.repository.url.full on their spans."
  if [ "$print" = 1 ]; then
    printf 'bluebox ask --env %s %s\n' "$(shq "$env")" "$(shq "$prompt")"
  else
    command -v bluebox >/dev/null 2>&1 || die "bluebox is not on PATH"
    exec bluebox ask --env "$env" "$prompt"
  fi
  ;;
*) usage;;
esac
