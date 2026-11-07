# Stage 7 Performance Workloads

## Engine

- Artillery image: artilleryio/artillery:2.0.22

## Upstream transaction workload

- repository: aws-containers/retail-store-sample-app
- tag: v1.6.2
- commit: 1a28474f2461459f42e6b393db59e7d1434d4aec
- local source: upstream/retail-v1.6.2/

The upstream scenario is retained unchanged and is the transaction profile.

## Browse profile

browse.yml is a Stage 7 read-only workload.

Each virtual user performs three configured HTTP actions:

1. GET /home
2. GET /catalog
3. GET /catalog/<product-id>

Its purpose is repeatable baseline and capacity-ramp testing without
creating checkout/order data.

## Load semantics

Artillery arrivalRate is virtual-user arrivals per second, not HTTP RPS.

Capacity reports must record actual HTTP request rate separately from
arrivalRate:

$$\text{HTTP RPS} = \text{arrivalRate (VU/s)} \times 3$$

## Capacity Envelope & Knee Summary

| Load Point | VU/s | Target RPS | Result | Key Observation |
|---|---|---|---|---|
| Baseline | 10 | 30 | PASS | 100% 200 OK, p95 ~26ms, zero errors |
| Capacity Ceiling | 13 | 39 | PASS | 33,750 requests, 100% 200 OK, p95 54–85ms, MySQL CPU ~0.45 core |
| Saturation Knee | 14 | 42 | SATURATED | MySQL CPU 0.748 core (limit 0.8), 2,856 VUs skipped, p95 8,213ms |
| Unserviceable | 15 | 45 | FAIL | Severe queue backup, ECONNREFUSED / ETIMEDOUT |

- Primary Bottleneck: `catalog-mysql-0` on `k8s-worker2` reaches its 0.8-core CPU limit under 14 VU/s (42 RPS), causing query latency to back up into upstream UI connection pools.

## Runtime image supply

The Kubernetes runtime remains air-gapped. Before executing a Stage 7 Artillery Job, `docker.io/artilleryio/artillery:2.0.22` must be present in the internal Registry.

The repeatable bootstrap path is:

`./infra/registry/seed-performance.sh`

The bootstrap source is pinned by digest, while Kubernetes keeps using the original `docker.io/artilleryio/artillery:2.0.22` image reference. Normal CRI resolution must continue through the internal Registry.
