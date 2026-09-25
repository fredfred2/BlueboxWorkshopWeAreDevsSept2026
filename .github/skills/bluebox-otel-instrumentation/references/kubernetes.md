# Kubernetes cluster monitoring

> **Scope: Bluebox-provisioned customer tenants only.** Applies to Kubernetes clusters in a customer workspace Bluebox provisions - no Dynatrace
> Operator, no ActiveGate. Does **not** apply to Bluebox's own EKS infrastructure (ADR-032: Dynatrace Operator + K8s-API-monitoring mode; rejects OTel
> K8s receivers there). If asked about Bluebox's own cluster, escalate.

Follow only when the user asks Bluebox to monitor a **Kubernetes cluster** (cluster/node/pod metrics and Kubernetes events), not when instrumenting a
single service. Cluster-side deployment, not repo-local SDK wiring, over the **same** OTLP endpoint and ingest token the main skill uses.

## What this gives Bluebox

- Node and pod resource metrics (CPU, memory, filesystem, network) from each node's kubelet.
- Cluster-level metrics and object state (nodes, pods, workloads, quotas).
- Kubernetes events (scheduling, restarts, OOMKills, evictions) as logs.
- `k8s.*` resource attributes on all of the above.

## Boundaries and gates

- **App instrumentation is unchanged.** Adds cluster/platform telemetry alongside per-service SDK instrumentation.
- **Cluster-scoped RBAC is privileged.** Needs a `ServiceAccount` + `ClusterRole` + `ClusterRoleBinding` with cluster-wide read on nodes, pods,
  events, workloads. Get explicit user approval before applying it; never apply cluster RBAC silently.
- **Same Bluebox ingest contract.** Hard rules 1, 7 and 8 apply unchanged; token lives in a Kubernetes `Secret` referenced by env.
- **Confirm the target.** Proceed only if the user runs Kubernetes and wants cluster monitoring; otherwise stay in the main skill.

## Prerequisites

- A running Kubernetes cluster and `kubectl` access with permission to create RBAC and workloads.
- The Bluebox OTLP endpoint. Run `bluebox otlp-endpoint` if unknown (main skill: exit-code handling).
- The Bluebox `Authorization` header value, supplied by the user into a Kubernetes `Secret` (below) per Hard rules 1 and 8.
- The **OpenTelemetry Collector Contrib** distribution (or any build with the `k8s_cluster`, `kubelet_stats`, `k8s_events`, `otlp` receivers, the
  `k8sattributes`, `transform`, `filter`, `cumulativetodelta` processors, and `k8s_leader_elector`/`health_check` extensions). Prefer a
  vendor-neutral Contrib build; do not require a vendor operator.

## Topology

Deploy **one DaemonSet** of the Collector in agent mode:

- every pod runs `kubelet_stats` for **its own node** (needs `K8S_NODE_NAME` = `spec.nodeName`);
- the `k8s_leader_elector` extension elects a **single** pod to run the cluster-scoped receivers (`k8s_cluster`, `k8s_events`), avoiding duplication
  across nodes.

A split node/cluster deployment also works but adds moving parts; prefer the single DaemonSet unless the split is needed.

## Secret (user supplies the auth header)

Tell the user to create the Secret **in their own terminal**; never run the block below yourself, and never offer it through this
shell or the agent's `!` prefix. Those have no hidden prompt, so the value lands in the transcript (Hard rule 1). Do not create
the Secret with a real value yourself. The user copies the whole `Authorization` value, scheme included - `Bearer <token>` or `Api-Token <token>`: what follows `Authorization=` inside the quotes of the line the Setup page's Copy token gives, without the `Authorization=` key itself, which the collector config adds (Hard rule 8).

**Avoid `--from-literal` and `echo '<value>'` with a real credential.** Both land in shell history and process arguments. The user types it into a hidden prompt in their own terminal, writes it to a fresh `mktemp` file (mode 600), and deletes it after:

```bash
# USER'S OWN TERMINAL ONLY — the agent hands this over and never runs it (Hard rule 1).
# Hidden prompt: the value reaches neither history nor process arguments; mktemp
# creates a fresh mode-600 file (a pre-existing path could carry looser bits).
read -rs -p 'Authorization value: ' BLUEBOX_OTLP_AUTH; echo
f="$(mktemp)" && printf '%s' "$BLUEBOX_OTLP_AUTH" > "$f"
kubectl create secret generic bluebox-otlp \
  --namespace <ns> \
  --from-file=otlp-auth="$f"
rm -f "$f"; unset BLUEBOX_OTLP_AUTH f
```

## RBAC (privileged, get approval)

```yaml
apiVersion: v1
kind: ServiceAccount
metadata: { name: otelcol-bluebox, labels: { app: otelcol-bluebox } }
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata: { name: otelcol-bluebox, labels: { app: otelcol-bluebox } }
rules:
  - apiGroups: [""]
    resources: [events, namespaces, namespaces/status, nodes, nodes/spec, nodes/stats,
                persistentvolumes, persistentvolumeclaims, pods, pods/status,
                replicationcontrollers, replicationcontrollers/status, resourcequotas, services]
    verbs: [get, list, watch]
  - apiGroups: [apps]
    resources: [daemonsets, deployments, replicasets, statefulsets]
    verbs: [get, list, watch]
  - apiGroups: [batch]
    resources: [jobs, cronjobs]
    verbs: [get, list, watch]
  - apiGroups: [autoscaling]
    resources: [horizontalpodautoscalers]
    verbs: [get, list, watch]
  - apiGroups: [coordination.k8s.io]
    resources: [leases]
    verbs: [get, list, watch, create, update, patch, delete]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: { name: otelcol-bluebox, labels: { app: otelcol-bluebox } }
roleRef: { apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: otelcol-bluebox }
subjects:
  - { kind: ServiceAccount, name: otelcol-bluebox, namespace: <ns> }
```

The `leases` write verbs are required by the leader-elector extension; the rest is cluster-wide read.

## Collector configuration

```yaml
extensions:
  health_check:
    endpoint: 0.0.0.0:13133
  k8s_leader_elector:
    auth_type: serviceAccount
    lease_name: bluebox-k8smonitoring
    lease_namespace: ${env:POD_NAMESPACE}

receivers:
  k8s_events:
    auth_type: serviceAccount
    k8s_leader_elector: k8s_leader_elector
  kubeletstats:
    auth_type: serviceAccount
    collection_interval: 10s
    node: ${env:K8S_NODE_NAME}
    metric_groups: [node, pod, container, volume]
  k8s_cluster:
    auth_type: serviceAccount
    collection_interval: 10s
    k8s_leader_elector: k8s_leader_elector

processors:
  cumulativetodelta:
    max_staleness: 25h                    # keep above the collection/scrape interval
  filter:
    error_mode: ignore
  k8sattributes:
    extract:
      metadata: [k8s.pod.name, k8s.pod.uid, k8s.namespace.name, k8s.node.name,
                 k8s.deployment.name, k8s.replicaset.name, k8s.statefulset.name,
                 k8s.daemonset.name, k8s.job.name, k8s.cronjob.name, k8s.container.name, k8s.cluster.uid]
    pod_association:                    # scraped data has no client connection; match on resource attributes
      - sources: [{from: resource_attribute, name: k8s.pod.uid}]
      - sources: [{from: resource_attribute, name: k8s.pod.name},
                  {from: resource_attribute, name: k8s.namespace.name}]
  transform:
    error_mode: ignore
    metric_statements: &k8s_workload
      - context: resource
        statements:
          - set(attributes["k8s.cluster.name"], "${env:CLUSTER_NAME}")
    log_statements: *k8s_workload

exporters:
  otlphttp/bluebox:
    endpoint: ${env:BLUEBOX_OTLP_ENDPOINT}                       # from `bluebox otlp-endpoint`
    headers:
      Authorization: ${env:BLUEBOX_OTLP_AUTH}                    # whole header value incl. scheme; from the Secret, never inlined

service:
  extensions: [health_check, k8s_leader_elector]
  pipelines:
    metrics/node:
      receivers: [kubeletstats]
      processors: [filter, k8sattributes, transform, cumulativetodelta]
      exporters: [otlphttp/bluebox]
    metrics/cluster:
      receivers: [k8s_cluster]
      processors: [k8sattributes, transform, cumulativetodelta]
      exporters: [otlphttp/bluebox]
    logs/events:
      receivers: [k8s_events]
      processors: [transform]
      exporters: [otlphttp/bluebox]
```

Notes:

- Scrapes **cluster/node/pod telemetry only**, with **no `otlp` receiver and no `traces` pipeline**: app services keep exporting their own
  traces/metrics/logs **directly** to Bluebox (per the main skill); doesn't route app telemetry through the cluster collector. A shared in-cluster
  OTLP gateway is a separate decision outside this reference. Do not add one here just to instrument apps.
- The exporter uses OTLP over `http/protobuf` to the Bluebox OTLP endpoint, same transport contract the app instrumentation uses.
- `k8s_events` is a maturing receiver; treat cluster events as best-effort, don't block the metrics pipelines on it.

## Required environment (Downward API + config)

Inject on the DaemonSet pod spec:

```yaml
env:
  - name: K8S_NODE_NAME
    valueFrom: { fieldRef: { fieldPath: spec.nodeName } }
  - name: POD_NAMESPACE
    valueFrom: { fieldRef: { fieldPath: metadata.namespace } }
  - name: CLUSTER_NAME
    value: "<a stable name for this cluster>"
  - name: BLUEBOX_OTLP_ENDPOINT
    value: "<bluebox otlp-endpoint output>"
  # Whole Authorization value, scheme included, as the Setup page renders it (Hard rule 8):
  # "Bearer <token>" for a platform token (dt0s16…), "Api-Token <token>" for a classic one (dt0c01…).
  - name: BLUEBOX_OTLP_AUTH
    valueFrom: { secretKeyRef: { name: bluebox-otlp, key: otlp-auth } }
```

Set the DaemonSet's `serviceAccountName: otelcol-bluebox`.

## Verify

- Apply RBAC (after approval), Secret, config, and the DaemonSet; confirm pods are `Running` and the `health_check` extension is healthy.
- Confirm the collector isn't erroring on export. A `401/403` is a secret/config issue, not code. The value isn't reaching the collector, or it
  carries the wrong scheme for the workspace's token kind; have the user re-copy it whole from the Setup page.
- The header lives in the Secret, where you cannot test it: before the `bluebox ask`, ask whether the Secret carries it and take the answer, as Workflow step 4 does for a variable in the user's terminal. No header is `blocked` (`no_token`), nothing asked.
- Ask Bluebox whether cluster telemetry is arriving, e.g.:

  ```bash
  bluebox ask "are Kubernetes cluster or pod metrics and events arriving for cluster <CLUSTER_NAME> in the last 15 minutes?"
  ```

- Report per the closing summary's three states: no answer from `bluebox ask` means `blocked` (`verify_unreadable`), never verified.

## Declared criticality (Bluebox critical-components ranking)

Bluebox reads a service's declared criticality from the `primary_tags.criticality` span resource attribute (`high`/`medium`/`low`) - the OTel-native
signal for the `critical_components` enricher; without it a service ranks on derived fragility alone (replica deficit, resource pressure, restarts).

**How to set it, SDK-side (the only supported path with direct export):**

Set the resource attribute in the service's environment:

```bash
OTEL_RESOURCE_ATTRIBUTES="primary_tags.criticality=high"
```

Or in code (example: Go SDK):

```go
res := resource.NewWithAttributes(
    semconv.SchemaURL,
    attribute.String("primary_tags.criticality", "high"),
)
```

Bluebox queries `primary_tags.criticality` on **app spans**, not collector-scraped K8s metrics. Since app services here export directly to Bluebox,
not through the cluster collector, a `k8sattributes` processor there can't set this attribute. SDK-side is the only path that works.
`OTEL_RESOURCE_ATTRIBUTES` on each service is sufficient; Bluebox reads it from the first matching span.

## Report

Summarize: cluster targeted, that cluster-scoped RBAC was applied with the user's approval, signals configured (node metrics, cluster metrics,
events), that the ingest token stayed in a Kubernetes Secret and was never committed, and verification status (verified vs blocked).
