# Orders PostgreSQL emptyDir to PVC migration

## Scope

This runbook migrates only the production Orders PostgreSQL data volume from `emptyDir` to a retained PVC.

It assumes the Stage 5 logical backup and isolated restore path has already been proven.

Accepted prerequisite:

- backup/restore PR: #42
- backup ID: `20260928T070335Z-9dc19d58`
- original database node: `k8s-worker1`
- external backup host: `k8s-master`
- isolated restore node: `k8s-worker2`
- application-level restore validation: PASS

## Why the migration is staged

The Retail Argo CD Application tracks `main` with automated sync, prune, and self-heal enabled.

A direct live `kubectl scale` or StatefulSet patch is therefore not a stable maintenance mechanism: Argo CD can reconcile the resource back to Git.

Changing the StatefulSet Pod template from `emptyDir` to a PVC also causes a normal RollingUpdate StatefulSet to recreate its Pod. The current `emptyDir` data must therefore be treated as disposable once the cutover state is applied.

## Preview overlay

`infra/migrations/stage5/orders-postgresql-pvc` is intentionally **not** the Argo CD source path.

It exists only to render and diff the intended maintenance cutover state before any production change.

The preview state declares:

- `checkout` replicas: 0
- `orders` replicas: 0
- `orders-postgresql` replicas: 0
- new PVC: `orders-postgresql-data`
- StorageClass: `local-path-retain`
- requested capacity: 4Gi
- PVC prune protection: `Prune=confirm`
- future PostgreSQL `data` volume: PVC instead of `emptyDir`

The StatefulSet is deliberately scaled to zero in the cutover preview. This avoids a race where Kubernetes could immediately create an empty production PostgreSQL Pod on the new PVC before the proven backup has been restored.

## Migration sequence

### Phase 1 — Freeze application writes

Declare and merge a maintenance state that scales:

- `checkout` to 0
- `orders` to 0

Keep `orders-postgresql` at 1 and keep its current `emptyDir`.

Acceptance:

- Checkout has no running application Pod
- Orders has no running application Pod
- PostgreSQL remains Ready
- the pre-migration marker still exists

This is the write-freeze boundary.

### Phase 2 — Final backup

While Checkout and Orders remain stopped, run the repository backup script against the still-running production PostgreSQL instance.

Require:

- `pg_dump -Fc` success
- archive is non-empty
- `pg_restore --list` succeeds
- external copy exists on `k8s-master`
- source/external SHA256 match
- known business marker is recorded

Record the final backup completion timestamp.

Do not continue without a valid external backup.

### Phase 3 — Stop the old database and declare PVC storage

Declare and merge the cutover state:

- Checkout remains 0
- Orders remains 0
- `orders-postgresql` becomes 0
- create `orders-postgresql-data`
- replace the StatefulSet `data.emptyDir` volume with the PVC

After Argo syncs this state, the old PostgreSQL Pod is gone and its emptyDir must be considered unrecoverable.

Rollback from this point depends on the proven logical backup.

### Phase 4 — Restore the PVC

Create a temporary PostgreSQL 16.1 restore Pod that:

- mounts `orders-postgresql-data`
- uses labels that are not selected by the production PostgreSQL Service
- uses the existing `orders-db` Secret without decoding it
- becomes the first consumer of the WaitForFirstConsumer PVC

Restore the final external backup with `scripts/restore-orders.sh`.

Require:

- external backup SHA256 still matches
- restore Pod receives the same archive SHA256
- `pg_restore` succeeds with exit-on-error / single-transaction
- expected business marker exists
- related order data exists

Delete the temporary restore Pod only after validation succeeds.

Do not delete the PVC.

### Phase 5 — Start production PostgreSQL and Orders

Declare:

- `orders-postgresql` replicas: 1
- PostgreSQL still mounts `orders-postgresql-data`
- `orders` replicas: 1
- `checkout` remains 0

Require:

- PVC Bound
- production PostgreSQL Ready
- production PostgreSQL Service points to `orders-postgresql-0`
- known marker exists in the production database
- Orders API returns the known marker

### Phase 6 — Resume Checkout

Declare `checkout` replicas: 1.

Require the normal checkout path to become available again.

Create a new post-migration test order through the normal UI flow and record its order ID.

This proves new writes reach the restored PVC-backed database.

### Phase 7 — Persistence drill

Perform one controlled replacement of `orders-postgresql-0`.

After the replacement Pod becomes Ready, require:

- original pre-migration marker still exists
- new post-migration marker still exists
- Orders API reads both expected records

This is the persistence acceptance test.

## Measured recovery / data-loss language

Do not claim a guaranteed RTO or RPO.

Record:

- final backup completion time
- cutover start time
- production application read-success time
- observed recovery duration
- confirmed order count before final backup
- confirmed order count after recovery

If the write freeze is established before the final backup and all confirmed markers are present after recovery, the accepted wording is:

> In this controlled recovery experiment, no confirmed Orders records were observed lost.

Do not generalize this to continuous RPO=0.

## Rollback boundary

Before Phase 3, the existing emptyDir PostgreSQL Pod remains the primary rollback path.

After Phase 3, the old emptyDir is gone. Rollback is backup-based:

1. keep Checkout and Orders stopped
2. keep the production StatefulSet at zero
3. recreate or clear the target PVC only after explicitly deciding to discard the failed restore
4. restore the last validated external backup
5. validate the marker before resuming applications

Never delete the last valid external backup during the migration.


## Accepted execution result

The runbook was executed successfully on 2026-09-28.

Final production state:

- PostgreSQL: `orders-postgresql-0`
- node: `k8s-worker2`
- PVC: `orders-postgresql-data`
- PV: `pvc-0dd9ab31-7885-495e-9864-2665898491a1`
- capacity: 4Gi
- StorageClass: `local-path-retain`
- reclaim policy: Retain
- pre-migration marker: PASS
- post-migration order: PASS
- Orders API read validation: PASS
- post-migration write validation: PASS
- Pod replacement persistence validation: PASS

Final backup:

- ID: `20260928T085552Z-9dc19d58`
- SHA256: `ed42fad85324f8cc682cb406d3a03a28943165cfc681726b59f7c7073d15d3dd`

Post-migration order:

- `9614fdec-30f6-4b27-8fa4-239105720f62`

Controlled Pod replacement:

- old UID: `4bf2b73d-2494-480f-af9b-e8dddd64fc3d`
- new UID: `7b12b5bd-7d7e-401f-a118-2f675a2cbb25`
- same PVC remounted: PASS
- old and new Orders records survived: PASS

This validates Pod-level persistence. It does not validate loss of the `k8s-worker2` node or cross-node storage failover.
