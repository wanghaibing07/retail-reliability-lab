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
arrivalRate.

## Runtime image supply

The Kubernetes runtime remains air-gapped. Before executing a Stage 7 Artillery Job, `docker.io/artilleryio/artillery:2.0.22` must be present in the internal Registry.

The repeatable bootstrap path is:

`./infra/registry/seed-performance.sh`

The bootstrap source is pinned by digest, while Kubernetes keeps using the original `docker.io/artilleryio/artillery:2.0.22` image reference. Normal CRI resolution must continue through the internal Registry.
