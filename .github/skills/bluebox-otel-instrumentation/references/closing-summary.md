# Closing summary (fixed shape)

End the run with these three blocks, in this order, built from what the run actually saw.
Nothing here that the run did not establish. One line first: "Time to first telemetry:
M min (expected L–H)", M from your first file change to the verification answer. L–H is
the plan's Expected line: 11.5 min for the run plus per service .NET 0.9, Java 1.2, Go
2.7, Node 2.8, other 1.5 min (the benchmark's calibration), 0.7 of the per-service part at
level 1 or 2, L and H at 0.8 and 1.2 of the sum.

1. **One table, one row per service in the inventory.** Every service you inventoried,
   in scope or not, exactly once, never grouped:

   | service | state | detail |
   |---|---|---|
   | pricing-service | reporting | traces, metrics, logs |
   | calculationservice | skipped | unbuildable_on_host — x86-only image, this host is arm64 |
   | problem-operator | skipped | out_of_scope — runs only under Kubernetes; the compose stack never deploys it |
   | cart | blocked | build_failed — `dotnet restore` NU1101 for OpenTelemetry.AutoInstrumentation; clears once the feed is in nuget.config |

   `reporting` means signals verified in-product, and the detail names which ones.
   `skipped` carries the census reason it was never in scope. `blocked` carries the
   concrete blocker and what would clear it. Those three words are the whole vocabulary:
   a service is in exactly one of them, and "configured", "done" or "partial" are not
   states. A service whose wiring you could not prove is `blocked`.

   The detail of every `skipped` or `blocked` row opens with exactly one reason token, then
   `—` and the concrete detail; a reason outside the set is written `other: <free text>`.
   Reason set:
   - `build_failed` — compile, test or image build failed after wiring, or the exporter guard of Hard rule 9 hit; detail names the error
   - `unbuildable_on_host` — known from the base image before building (arch, platform)
   - `no_runtime` — the stack needs a container runtime and the Inventory probe found none
     usable (no docker/podman/nerdctl, or its daemon down); nothing was built or started
   - `registry_unreachable` — the reachability probe of Workflow step 1, or Hard rule 9's version
     lookup, could not connect to the container registry or package index the build needs
     (`http=000`, a connect or DNS failure); nothing was pulled, installed or built from it,
     and nothing in the run was started
   - `endpoint_unreachable` — the reachability probe could not connect to the OTLP endpoint
     before any run (`http=000`, no header sent); wired and build-verified, never started
   - `port_busy` — the service could not bind its port and no free one was taken
   - `no_endpoint` — no OTLP endpoint was available (no template, `otlp-endpoint` exit 2)
   - `no_token` — no ingest header where the run's services read it (the named env location, a Secret, a collector or function configuration); nothing was started or verified
   - `egress_blocked` — the app ran but exports could not leave the host/container network
     (connection refused or timed out on the endpoint step 2 printed)
   - `auth_rejected` — the exporter logged 401/403: the `Authorization` value or its scheme
     (Hard rule 8), still rejected after one fix
   - `wire_rejected` — the exporter logged 415: JSON on the wire where ingest takes
     `http/protobuf` only (Hard rule 7), still rejected after one fix
   - `endpoint_rejected` — the exporter logged 404, or its host name never resolved: the
     endpoint value (host or path) differs from what step 2 printed
   - `signal_unwired` — no export path for a selected signal after the traffic (the code
     registers no reader, bridge or provider for it) and the wiring gap was not closed in the
     run
   - `verify_absent` — the app ran and exported, the verification found nothing in the window
     (or only entity-derived `dt.*` keys)
   - `verify_unreadable` — the verification answered, but not in a form you could judge
   - `pii_withheld` — held below the chosen level because its records carry personal data
   - `already_instrumented` — exports OpenTelemetry already; nothing to add, only to route
   - `oneagent_sdk_inactive` — carries a OneAgent SDK that emits nothing without a OneAgent
   - `version_pinned` — held to an older instrumentation line by the repo's runtime version
   - `out_of_scope` — census reason (browser app, off-the-shelf image, never deployed)
   - `user_declined` — the developer kept it out at the question
   - `other: <free text>` — anything else; more than one in ten rows means a missing token
   The token is what gets counted across runs; the detail after it is for the reader. A
   `pii_withheld` or `version_pinned` hold on a `reporting` service goes in Limitations,
   opening the line with the same token.

2. **Limitations.** Only what this run's facts support: a service that serves no inbound
   HTTP has no request metrics, infrastructure (databases, brokers, proxies) is not covered
   without a collector, a service kept at level 2 exports no logs and why. Do not list
   limitations you did not hit.

3. **Next steps.** What the developer does now: where to look in Bluebox, what to run to
   re-verify, and the one thing that would move a `blocked` service to `reporting`. When
   anything is blocked, this block names a command, because "blocked" without the thing to
   run is not an answer:

   > **Limitations**: `db` and `rabbitmq` are infrastructure and need a collector, which this
   > run did not add. Six services stay at level 2, so they export no logs.
   >
   > **Next steps**: open the environment view for `docker-compose`. To verify
   > problem-operator, deploy the chart to a cluster and re-run
   > `bluebox ask --env docker-compose "which services have spans arriving?"`.

Also state, once: the files you changed, the env vars the user must supply, and anything
that reached your own output that should not have. Name it without reproducing it ("the
ingest token was printed by `<compose> config`; rotate it on the Bluebox Setup page,
`<bluebox-host>/setup`"), never the value or a fragment. Your final message is recorded
and read by others.

For deeper query patterns load the **`production-query`** skill.
