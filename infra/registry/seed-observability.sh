#!/usr/bin/env bash
set -euo pipefail

# The source image must already be present in containerd's k8s.io namespace.
# Pull it from the approved external/OCI path before running this script.
source_image='quay.io/prometheus/prometheus:v3.13.3'
registry='192.168.88.3:5000'
destination="${registry}/prometheus/prometheus:v3.13.3"
stage='seed.local/prometheus:v3.13.3'
hosts_dir='/etc/containerd/certs.d'

sudo ctr -n k8s.io images ls -q | grep -Fx -- "$source_image" >/dev/null || {
  printf 'Source image is missing: %s\n' "$source_image" >&2
  exit 1
}

sudo ctr -n k8s.io images rm "$stage" >/dev/null 2>&1 || true
sudo ctr -n k8s.io images convert --platform linux/amd64 "$source_image" "$stage"
sudo ctr -n k8s.io images push --local \
  --hosts-dir "$hosts_dir" \
  --max-concurrent-uploaded-layers 1 \
  "$destination" "$stage"
sudo ctr -n k8s.io images rm "$stage" >/dev/null 2>&1 || true
printf 'SEED_OK|%s|%s\n' "$source_image" "$destination"
