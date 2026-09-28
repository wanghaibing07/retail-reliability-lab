# Orders PostgreSQL Backup

## Scope

Stage 5 validates one recovery case deeply: the Retail Orders PostgreSQL database.

It does not claim full disaster recovery for MySQL, RabbitMQ, Redis, DynamoDB, the Kubernetes control plane, or the VMware host.

## Source state

At the start of Stage 5:

- StatefulSet: `orders-postgresql`
- PostgreSQL: 16.1
- database: `orders`
- data path: `/data/pgdata`
- storage: `emptyDir`
- source workload node during the accepted recovery experiment: `k8s-worker1`

A Pod replacement can therefore destroy the current database data until production is migrated to persistent storage.

## Backup method

`scripts/backup-orders.sh` uses PostgreSQL custom archive format:

```text
pg_dump -Fc
```

The script is fail-closed:

1. write the source archive as `*.partial`
2. require a non-empty archive
3. require `pg_restore --list` to parse it
4. calculate the source SHA256
5. copy the archive outside the source database VM
6. require the external SHA256 to match
7. write manifest and validation metadata
8. only then rename the external `*.partial` file to its final `.dump` name

A backup archive is not committed to Git.

## Failure-domain terminology

These fields have distinct meanings and must not be merged:

- `original_database_node`: Kubernetes node/VM that ran the source PostgreSQL workload
- `external_backup_host`: host that stores the copied backup artifact
- `restore_node`: node/VM that runs the isolated restore target

For the accepted experiment:

```text
original_database_node = k8s-worker1
external_backup_host   = k8s-master
restore_node           = k8s-worker2
```

The external copy is outside the source database VM, but all VMware guests still share the same underlying host. This is not off-site disaster recovery.

## Accepted backup experiment

Backup ID:

```text
20260928T070335Z-9dc19d58
```

Observed result:

- backup duration: 4s
- archive size: 6357 bytes
- SHA256: `e5a8f61b74cb300adcb10d34ec4cb458d11a6d4b7329e02d6b566005abd49e3c`
- archive validation: PASS
- external SHA256 match: PASS
- business marker recorded before backup:
  `f160b51e-6c7d-4479-acc6-96cdcd7f83c0`

The backup was later restored successfully into an isolated PostgreSQL instance on another worker. That restore evidence, not `pg_restore --list` alone, establishes recoverability.

## Security

The backup workflow does not decode or print the `orders-db` Secret.

Database tools run inside the PostgreSQL container and consume the existing `POSTGRES_USER` / `POSTGRES_PASSWORD` environment.

Do not commit:

- `.dump` archives
- decoded Secret values
- kubeconfig
- credentials
- private keys

## RPO boundary

Stage 5 currently validates a manually created backup and restore.

It does not establish a continuous backup schedule or a guaranteed RPO.


## Final migration backup

After Checkout and Orders were scaled to zero, the final migration backup was created while production PostgreSQL was still running on the original `emptyDir`.

- backup ID: `20260928T085552Z-9dc19d58`
- source Pod: `orders-postgresql-0`
- original database node: `k8s-worker1`
- external backup host: `k8s-master`
- archive size: 6357 bytes
- SHA256: `ed42fad85324f8cc682cb406d3a03a28943165cfc681726b59f7c7073d15d3dd`
- duration: 6s
- archive validation: PASS
- external SHA256 match: PASS
- pre-migration business marker remained present after backup

This final backup was restored into `orders-postgresql-data` during the production PVC migration.

The controlled experiment observed no loss of confirmed Orders records, but this does not establish a guaranteed continuous RPO.
