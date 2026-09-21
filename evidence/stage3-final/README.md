# Stage 3 Final Evidence

Stage 3 Argo CD / GitOps closeout evidence.

Validation date: 2026-09-22

## Live-validated baseline

The live functional validation was performed against:

`9218facf4a80b7dea714c52d0cdb8ee006b42fc1`

This is the application/platform baseline validated before the documentation-only
Stage 3 closeout PR. The final `stage3-v0.4` tag may therefore point to a newer
commit containing only closeout documentation and evidence changes.

## Verified state

- Retail Application: `Synced`
- Retail Application health: `Healthy`
- Argo revision matched the validated Git revision
- Automated Sync: enabled
- Self Heal: enabled
- Auto Prune: enabled
- `allowEmpty`: disabled
- `catalog-mysql`: `Prune=confirm`
- `orders-postgresql`: `Prune=confirm`
- `orders-rabbitmq`: `Prune=confirm`
- temporary `gitops-prune-probe`: absent
- Retail desired state: 10 workloads / 10 Services
- all active Pods Ready
- all expected Services had Ready EndpointSlices
- business HTTP check: `200`
- declarative Argo platform versus live: `kubectl diff --server-side` returned `0`

## Files

- `revision.txt` — live-validated Git baseline
- `argocd-application.txt` — Application sync/health/automation state
- `prune-guards.txt` — StatefulSet destructive-operation guards
- `prune-probe.txt` — Auto Prune probe final state
- `argocd-platform-diff.txt` — platform drift result
- `verify-*.log` — complete Retail verification
- `verify-*-pods.txt` — Pod snapshot
- `verify-*-services.txt` — Service snapshot
- `verify-*-endpointslices.txt` — EndpointSlice snapshot

## Boundaries

This evidence does not prove:

- production-grade HA
- database durability or restore capability
- data integrity solely from HTTP 200
- that Incident #003's underlying VMware guest-egress fault is fixed

Retail MySQL, PostgreSQL and RabbitMQ still use `emptyDir`. Backup and restore
are intentionally deferred to Stage 5.
