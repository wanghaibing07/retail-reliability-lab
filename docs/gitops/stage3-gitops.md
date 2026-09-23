# Stage 3: Argo CD / GitOps

## Goal

Make Git the single source of desired Kubernetes application state while keeping delivery observable, testable, recoverable, and bounded by destructive-operation safeguards.

## Desired-State Path

Retail desired state is:

```text
infra/apps/retail
```

The following paths now use the same desired state:

```text
Argo CD
CI
deploy.sh
prepull-images.sh
```

The old direct vendor-manifest deployment path is no longer a second source of truth.

## CI Gate

Changes follow:

```text
feature branch
→ Pull Request
→ required validate check
→ merge to protected main
```

CI validates:

- Bash syntax
- ShellCheck
- image-tag policy regression tests
- Retail Kustomize render
- Argo CD platform Kustomize render
- Argo CD CRD presence
- kubeconform schema validation
- rejection of `latest` image tags

The Argo CD CRDs use the narrow exception:

```text
-skip CustomResourceDefinition
```

rather than globally ignoring missing schemas.

## Declarative Argo CD Platform

Argo CD platform configuration is managed from:

```text
infra/argocd/platform
```

The repository declares:

```text
application.resourceTrackingMethod: annotation
```

and the repo-server retry mitigation:

```text
ARGOCD_GIT_ATTEMPTS_COUNT=3
```

A server-side diff was reviewed before takeover.

After apply, the platform reached:

```text
Git desired state = live Argo CD state
```

with final:

```text
kubectl diff --server-side -k infra/argocd/platform
rc=0
```

## Resource Tracking

Argo ownership uses:

```text
argocd.argoproj.io/tracking-id
```

Business identity continues to use labels such as:

```text
app.kubernetes.io/instance=catalog
```

The two concepts are intentionally kept separate.

The live audit observed:

```text
33/33 resources with argocd.argoproj.io/tracking-id
0/33 resources with argocd.argoproj.io/instance
```

The tracking mode is now also explicitly declared in Git.

See [ADR 001](../decisions/001-argocd-resource-tracking.md).

## Manual Sync

PR #6 changed the UI replica count from 1 to 2.

The release path was:

```text
Git change
→ Pull Request
→ CI
→ merge
→ OutOfSync
→ Manual Sync
→ UI 2/2
```

This proved the initial controlled GitOps delivery path.

## Auto Sync

Automated sync was enabled with prune and self-heal initially disabled.

A harmless UI Service annotation was then added through Git.

After merge:

```text
Git main
→ Argo polling
→ automatic reconciliation
→ live annotation present
```

No Manual Sync was used.

A later PR removed the annotation and Argo automatically reconciled the cleanup.

Result:

```text
Auto Sync = PASS
```

Evidence:

```text
evidence/gitops-auto-sync
```

## Self Heal

Git desired state kept:

```text
UI replicas = 2
```

The live Deployment was manually drifted to:

```text
replicas = 1
```

No Git commit and no Manual Sync followed.

Argo CD automatically restored:

```text
spec=2
ready=2
```

Retail verification and HTTP checks passed afterward.

Result:

```text
Self Heal = PASS
```

Evidence:

```text
evidence/gitops-self-heal
```

## Prune Safety

Before enabling automatic pruning, the three data-bearing StatefulSets were protected with:

```text
argocd.argoproj.io/sync-options: Prune=confirm
```

Protected resources:

```text
catalog-mysql
orders-postgresql
orders-rabbitmq
```

This prevents the Application-level automatic prune policy from silently deleting these workloads.

The databases still use `emptyDir`; this guardrail does not provide persistence or backup.

## Auto Prune

Application policy is:

```yaml
syncPolicy:
  automated:
    enabled: true
    prune: true
    selfHeal: true
    allowEmpty: false
```

Auto Prune was tested using only a disposable ConfigMap:

```text
gitops-prune-probe
```

Experiment:

```text
PR #20
Git adds ConfigMap
→ Argo creates ConfigMap

PR #21
Git removes ConfigMap
→ no Manual Sync
→ no kubectl delete
→ Argo automatically removes ConfigMap
```

The final Stage 3 validation confirmed that the probe is absent.

Result:

```text
Auto Prune = PASS
```

Evidence:

```text
evidence/gitops-auto-prune
```

## Verification Model

`verify.sh` validates from Git expected state rather than discovering whatever happens to exist live.

It checks:

1. expected workloads exist
2. Deployment / StatefulSet rollout
3. active Pods are Ready
4. terminal Pods do not pollute readiness
5. expected Services exist
6. Service API failures are not hidden
7. Ready EndpointSlices exist
8. UI HTTP returns 2xx

A negative test previously proved that a Git-expected but missing Deployment causes verification to fail.

Principle:

```text
A validator must prove both:
healthy state passes
and
broken state is actually detected
```

## Destructive Operation Boundary

`destroy.sh` is GitOps-aware and fail-closed.

It includes:

- `--dry-run`
- interactive confirmation
- `--yes`
- Argo Application checks
- finalizer awareness
- StatefulSet `emptyDir` warning
- Argo management shutdown before namespace deletion
- distinction between NotFound and API/RBAC/network failure

Principle:

```text
Unable to prove safe
≠ safe to delete
```

## Incident #003

Argo CD repo-server intermittently failed direct GitHub access.

The incident reproduced again during the Kubernetes 1.36.4 rebuild.

The latest investigation ruled out the Kubernetes application/network stack as a sufficient explanation and narrowed the supported failure boundary to an intermittent direct GitHub network path outside the validated guest SNAT path.

Current controls are:

```text
ARGOCD_GIT_ATTEMPTS_COUNT=3
repository-specific proxy=http://192.168.88.1:7890
```

The proxy path was repeatedly validated from both the node and repo-server.

This is documented as a mitigation, not as proof that the direct-path root cause has been repaired.

See:

```text
docs/incidents/003-argocd-repo-server-github-timeout/README.md
```

## Post-Stage-3 Rebuild Validation

On 2026-09-23 the lab cluster was rebuilt onto Kubernetes 1.36.4.

The recovery path validated:

```text
new control plane
→ Flannel
→ worker rejoin
→ retained Registry restore
→ dynamic storage restore
→ Argo CD platform restore
→ Retail Application reconciliation
→ verify.sh
```

Final state:

```text
3/3 Kubernetes Nodes Ready
Argo Application Synced / Healthy
Git revision 3c5e7c088cc93402d4b947443738a342b0fe863d
10/10 workloads verified
all selected Services have Ready EndpointSlices
11/11 Retail Pods Ready
business HTTP 200
```

The repo-server was restarted and a hard Application refresh was performed afterward. The Application remained Synced/Healthy.

This gives an additional real rebuild proof for the Stage 1 and Stage 3 reproducibility claims.

See [Decision 002](../decisions/002-kubernetes-136-rebuild.md).

## Final Stage 3 Validation

The final validation confirmed:

```text
Application = Synced / Healthy
Auto Sync = enabled
Self Heal = enabled
Auto Prune = enabled
allowEmpty = false
3 StatefulSets = Prune=confirm
prune probe = absent
Retail verify = PASS
business HTTP = PASS
Argo platform diff = 0
```

Stage 3 therefore demonstrates:

```text
protected Git change
→ required CI
→ desired-state reconciliation
→ drift correction
→ controlled pruning
→ workload/service/business validation
→ auditable evidence
```

## Boundaries

Stage 3 does not claim:

- production-grade HA
- database persistence
- database backup or restore
- complete disaster recovery
- Incident #003 root-cause remediation
- HTTP 200 as proof of data integrity

Those concerns belong to later stages.

## Next Stage

Stage 4 focuses on Observability.

The objective is not merely to install monitoring components.

The required engineering loop is:

```text
Metrics
→ Alert
→ Incident
→ Diagnosis
→ Recovery
→ Evidence
```
