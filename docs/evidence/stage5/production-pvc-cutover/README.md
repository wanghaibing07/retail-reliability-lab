# Stage 5 Production PVC Cutover Evidence

Date: 2026-09-28

## Result

Production Orders PostgreSQL was migrated from `emptyDir` to a retained PVC and validated through both reads and new writes.

```text
write freeze
-> final pg_dump
-> stop old emptyDir PostgreSQL
-> create retained PVC
-> restore final backup into PVC
-> production StatefulSet takes over PVC
-> Orders API read validation
-> Checkout resumed
-> new order write validation
-> controlled PostgreSQL Pod replacement
-> old + new order validation
```

## Final backup

- backup ID: `20260928T085552Z-9dc19d58`
- source node: `k8s-worker1`
- external backup host: `k8s-master`
- archive size: 6357 bytes
- SHA256: `ed42fad85324f8cc682cb406d3a03a28943165cfc681726b59f7c7073d15d3dd`
- duration: 6s
- archive validation: PASS
- external SHA256 match: PASS

## Production persistent storage

- PVC: `orders-postgresql-data`
- capacity: 4Gi
- access mode: RWO
- StorageClass: `local-path-retain`
- PV: `pvc-0dd9ab31-7885-495e-9864-2665898491a1`
- reclaim policy: Retain
- node affinity: `k8s-worker2`

## Restore

The final backup was restored into the production PVC through a temporary isolated PostgreSQL 16.1 Pod.

- restore SHA256: matched
- `pg_restore`: PASS
- measured database restore: 0.365s
- orders: 1
- order_items: 1
- shipping_addresses: 1

Pre-migration marker:

```text
f160b51e-6c7d-4479-acc6-96cdcd7f83c0
```

Marker validation: PASS.

The temporary restore Pod was deleted before the production StatefulSet was resumed.

## Production takeover

Production `orders-postgresql-0`:

- Ready: PASS
- node: `k8s-worker2`
- PVC: `orders-postgresql-data`
- production Service endpoint: Ready
- pre-migration marker: PASS

Orders application was then resumed and returned the same marker through the real production Orders API.

## Post-migration write

Checkout was resumed after database and Orders API read validation.

New frontend order:

```text
9614fdec-30f6-4b27-8fa4-239105720f62
```

Validation:

- new order exists in PostgreSQL: PASS
- new order exists in Orders API: PASS
- old order still exists: PASS
- application write validation: PASS

## Pod replacement persistence

Production PostgreSQL Pod was deliberately deleted once.

Before:

```text
UID=4bf2b73d-2494-480f-af9b-e8dddd64fc3d
PVC=orders-postgresql-data
```

After:

```text
UID=7b12b5bd-7d7e-401f-a118-2f675a2cbb25
node=k8s-worker2
PVC=orders-postgresql-data
```

After replacement:

- pre-migration order: present
- post-migration order: present
- Orders API old marker: PASS
- Orders API new marker: PASS
- persistence validation: PASS

## Accepted statement

> 已验证 Orders PostgreSQL 数据库的备份、持久化和隔离恢复能力。

For this controlled experiment, no confirmed Orders records were observed lost.

## Not demonstrated

This evidence does not demonstrate:

- worker2 node-loss recovery
- cross-node storage failover
- off-site disaster recovery
- continuous backup coverage or guaranteed RPO
- a guaranteed production RTO
- distributed-consistent recovery of all Retail stateful components
