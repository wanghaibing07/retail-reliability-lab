# Stage 5 Orders Restore Evidence — 20260928T070335Z-9dc19d58

## Result

The Orders PostgreSQL recovery path was demonstrated end-to-end.

```text
k8s-worker1 PostgreSQL
-> pg_dump -Fc
-> k8s-master external backup copy
-> SHA256 verification
-> k8s-worker2 isolated PostgreSQL/PVC
-> pg_restore
-> database marker validation
-> Orders 1.6.2 application marker validation
```

## Identity

- backup ID: `20260928T070335Z-9dc19d58`
- original database node: `k8s-worker1`
- external backup host: `k8s-master`
- restore node: `k8s-worker2`
- PostgreSQL: 16.1
- business marker: `f160b51e-6c7d-4479-acc6-96cdcd7f83c0`

Do not describe `k8s-master` as the original database source node. It is the host containing the external backup copy used as the restore source.

## Backup

- archive format: PostgreSQL custom archive
- size: 6357 bytes
- SHA256:
  `e5a8f61b74cb300adcb10d34ec4cb458d11a6d4b7329e02d6b566005abd49e3c`
- measured backup duration: 4s
- source/external SHA256: match
- archive inventory: readable

## Isolated restore

Restore target:

- Pod: `orders-postgresql-restore-s5`
- PVC: `orders-postgresql-restore-data`
- PV: `pvc-def13718-be19-45e3-870f-ba0a52e1f339`
- node affinity: `k8s-worker2`

Production endpoint:

```text
orders-postgresql-0
```

Restore endpoint:

```text
orders-postgresql-restore-s5
```

The target public schema contained zero tables before restore.

## Restored data

After `pg_restore`:

```text
orders             = 1
order_items        = 1
shipping_addresses = 1
```

The selected order existed once with one item and one shipping-address row.

Database validation: PASS.

## Application validation

An isolated Orders 1.6.2 application connected to the restored PostgreSQL database and returned the same business marker.

Application validation: PASS.

## Recovery measurement

```text
restore_started_at                    2026-09-28T07:40:25.723923664Z
database_restore_completed_at         2026-09-28T07:40:26.262383907Z
data_validation_completed_at          2026-09-28T07:40:26.646771021Z
application_validation_completed_at   2026-09-28T07:41:47.007423184Z
measured_recovery_seconds              81.285
```

This is an observed recovery duration for the accepted experiment. It is not a guaranteed RTO.

The experiment also does not establish a continuous RPO guarantee.

## pg_restore log note

The original accepted restore did not use `--verbose`, so `pg_restore.log` is empty even though the command exited successfully.

This does not invalidate the recovery result because the restored schema/data, marker relationships, and application read were independently verified afterward.

The repository restore script now uses `pg_restore --verbose` so future recovery runs produce explicit progress evidence.

## Artifacts

The local evidence directory contains:

- `backup-manifest.json`
- `backup-validation.json`
- `archive.list`
- `backup.log`
- `pg_restore.log`
- `restore-timing.env`
- `restore-runtime.txt`
- `database-validation.txt`
- `application-validation.txt`

The database `.dump` is intentionally not committed to Git.

## Boundary

This evidence demonstrates Orders PostgreSQL backup and isolated recovery.

It does not demonstrate whole-Retail distributed disaster recovery.
