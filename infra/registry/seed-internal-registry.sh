#!/usr/bin/env bash
set -euo pipefail

registry='192.168.88.3:5000'
hosts_dir='/etc/containerd/certs.d'
stage_counter=0

push_image() {
  local source="$1"
  local destination="$2"
  local stage="seed.local/image:${stage_counter}"
  stage_counter=$((stage_counter + 1))

  printf 'SEED_BEGIN|%s|%s\n' "$source" "$destination"
  sudo ctr -n k8s.io images rm "$stage" >/dev/null 2>&1 || true
  sudo ctr -n k8s.io images convert --platform linux/amd64 "$source" "$stage"
  sudo ctr -n k8s.io images push --local \
    --hosts-dir "$hosts_dir" \
    --max-concurrent-uploaded-layers 1 \
    "$destination" "$stage"
  sudo ctr -n k8s.io images rm "$stage" >/dev/null 2>&1 || true
  printf 'SEED_OK|%s|%s\n' "$source" "$destination"
}

# Project images. Destination paths intentionally preserve the path after the
# original registry host so containerd hosts.toml can mirror the existing refs.
push_image public.ecr.aws/aws-containers/retail-store-sample-catalog:1.6.2 \
  "$registry/aws-containers/retail-store-sample-catalog:1.6.2"
push_image public.ecr.aws/docker/library/mysql:8.0 \
  "$registry/docker/library/mysql:8.0"
push_image public.ecr.aws/aws-containers/retail-store-sample-cart:1.6.2 \
  "$registry/aws-containers/retail-store-sample-cart:1.6.2"
push_image public.ecr.aws/aws-dynamodb-local/aws-dynamodb-local:1.25.1 \
  "$registry/aws-dynamodb-local/aws-dynamodb-local:1.25.1"
push_image public.ecr.aws/aws-containers/retail-store-sample-orders:1.6.2 \
  "$registry/aws-containers/retail-store-sample-orders:1.6.2"
push_image public.ecr.aws/docker/library/postgres:16.1 \
  "$registry/docker/library/postgres:16.1"
push_image public.ecr.aws/docker/library/rabbitmq:3-management \
  "$registry/docker/library/rabbitmq:3-management"
push_image public.ecr.aws/aws-containers/retail-store-sample-checkout:1.6.2 \
  "$registry/aws-containers/retail-store-sample-checkout:1.6.2"
push_image docker.io/library/redis:6.0-alpine \
  "$registry/library/redis:6.0-alpine"
push_image public.ecr.aws/aws-containers/retail-store-sample-ui:1.6.2 \
  "$registry/aws-containers/retail-store-sample-ui:1.6.2"

# Worker and shared cluster images needed for a restart without upstream pulls.
push_image docker.io/library/busybox:1.36.1 \
  "$registry/library/busybox:1.36.1"
push_image registry.aliyuncs.com/google_containers/kube-proxy:v1.36.4 \
  "$registry/google_containers/kube-proxy:v1.36.4"
push_image registry.aliyuncs.com/google_containers/pause:3.10.2 \
  "$registry/google_containers/pause:3.10.2"
push_image ghcr.io/flannel-io/flannel-cni-plugin:v1.9.1-flannel3 \
  "$registry/flannel-io/flannel-cni-plugin:v1.9.1-flannel3"
push_image ghcr.io/flannel-io/flannel:v0.28.9 \
  "$registry/flannel-io/flannel:v0.28.9"
push_image rancher/local-path-provisioner:v0.0.36 \
  "$registry/rancher/local-path-provisioner:v0.0.36"

printf 'SEED_COMPLETE\n'
