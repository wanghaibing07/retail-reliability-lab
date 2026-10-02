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
