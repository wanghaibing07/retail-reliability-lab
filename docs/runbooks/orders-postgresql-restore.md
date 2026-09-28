# Orders PostgreSQL Restore Runbook

## Purpose

Recover an Orders PostgreSQL custom-format backup into an isolated database without modifying the production `orders-postgresql` workload.

This runbook is the accepted Stage 5 recovery path.

## Preconditions

Before restore:

- use a backup whose SHA256 is known
- the backup must be outside the original database VM
- the restore target must be isolated from the production PostgreSQL Service
- the restore target database must be empty
- use a compatible PostgreSQL 16.x image
- never decode or print `orders-db` Secret values

## 1. Restore target

The accepted experiment used:

- namespace: `retail`
- Pod: `orders-postgresql-restore-s5`
- Service: `orders-postgresql-restore`
- PVC: `orders-postgresql-restore-data`
- StorageClass: `local-path-retain`
- restore node: `k8s-worker2`
- image: `public.ecr.aws/docker/library/postgres:16.1`

The restore Pod uses different names and labels from production while reusing the existing `orders-db` Secret without decoding it.

Before restore, verify:

```text
production Service -> orders-postgresql-0
restore Service    -> orders-postgresql-restore-s5
```

Do not continue if the restore Pod is selected by the production Service.

## 2. Restore the archive

Run:

```bash
MARKER_ID='f160b51e-6c7d-4479-acc6-96cdcd7f83c0'
BACKUP='/home/k8sadmin/retail-backups/orders/20260928T070335Z-9dc19d58/orders-20260928T070335Z-9dc19d58.dump'
SHA='e5a8f61b74cb300adcb10d34ec4cb458d11a6d4b7329e02d6b566005abd49e3c'

./scripts/restore-orders.sh \
  --backup-file "$BACKUP" \
  --restore-pod orders-postgresql-restore-s5 \
  --expected-sha "$SHA" \
  --marker-id "$MARKER_ID" \
  --log-file /home/k8sadmin/retail-backups/orders/restore-pg_restore.log
```

The script refuses:

- a checksum mismatch
- a restore target selected by the production PostgreSQL Service
- a non-empty target database
- an unreadable archive
- a failed `pg_restore`
- a missing marker when `--marker-id` is supplied

The restore uses:

```text
--verbose
--exit-on-error
--single-transaction
--no-owner
--no-acl
```

`--single-transaction` prevents a partially applied restore from being accepted.

## 3. Database validation

At minimum verify:

- expected tables exist
- expected row counts exist
- the selected order ID exists exactly once
- related order item and shipping-address rows exist

The accepted experiment restored:

```text
orders             = 1
order_items        = 1
shipping_addresses = 1
```

Marker:

```text
f160b51e-6c7d-4479-acc6-96cdcd7f83c0
```

## 4. Application validation

Database validation alone is not the Stage 5 acceptance boundary.

Start the same Orders application version against the isolated PostgreSQL endpoint:

```text
public.ecr.aws/aws-containers/retail-store-sample-orders:1.6.2
```

Configure:

```text
RETAIL_ORDERS_PERSISTENCE_PROVIDER=postgres
RETAIL_ORDERS_PERSISTENCE_ENDPOINT=orders-postgresql-restore:5432
RETAIL_ORDERS_PERSISTENCE_NAME=orders
RETAIL_ORDERS_MESSAGING_PROVIDER=in-memory
```

Read `GET /orders` and require the selected marker to be returned.

Using in-memory messaging prevents the validation application from publishing restore-test events into the production RabbitMQ path.

## 5. Accepted recovery measurement

The accepted experiment recorded:

```text
restore_started_at                    2026-09-28T07:40:25.723923664Z
database_restore_completed_at         2026-09-28T07:40:26.262383907Z
data_validation_completed_at          2026-09-28T07:40:26.646771021Z
application_validation_completed_at   2026-09-28T07:41:47.007423184Z
```

Measured restore start to application read:

```text
81.285s
```

This is a measured recovery time for this experiment, not a guaranteed production RTO.

## 6. Cleanup boundary

Do not delete the isolated restore PVC until the evidence has been reviewed and Stage 5 no longer needs the recovered database.

Because `local-path-retain` retains storage, cleanup must be deliberate.

Never use this runbook with the production `orders-postgresql-0` Pod as the restore target.
