#!/usr/bin/env bash
set -euo pipefail

registry='192.168.88.3:5000'
stage_counter=0

push_image() {
  local source="$1"
  local destination="$2"
  local stage="seed-control.local/image:${stage_counter}"
  stage_counter=$((stage_counter + 1))
  printf 'SEED_BEGIN|%s|%s\n' "$source" "$destination"
  sudo ctr -n k8s.io images rm "$stage" >/dev/null 2>&1 || true
  sudo ctr -n k8s.io images convert --platform linux/amd64 "$source" "$stage"
  sudo ctr -n k8s.io images push --local \
    --hosts-dir /etc/containerd/certs.d \
    --max-concurrent-uploaded-layers 1 \
    "$destination" "$stage" >/dev/null
  sudo ctr -n k8s.io images rm "$stage" >/dev/null 2>&1 || true
  printf 'SEED_OK|%s|%s\n' "$source" "$destination"
}

push_image registry.aliyuncs.com/google_containers/coredns:v1.10.1 \
  "$registry/google_containers/coredns:v1.10.1"
push_image registry.aliyuncs.com/google_containers/etcd:3.5.9-0 \
  "$registry/google_containers/etcd:3.5.9-0"
push_image registry.aliyuncs.com/google_containers/kube-apiserver:v1.28.15 \
  "$registry/google_containers/kube-apiserver:v1.28.15"
push_image registry.aliyuncs.com/google_containers/kube-controller-manager:v1.28.15 \
  "$registry/google_containers/kube-controller-manager:v1.28.15"
push_image registry.aliyuncs.com/google_containers/kube-scheduler:v1.28.15 \
  "$registry/google_containers/kube-scheduler:v1.28.15"

printf 'SEED_CONTROL_COMPLETE\n'
