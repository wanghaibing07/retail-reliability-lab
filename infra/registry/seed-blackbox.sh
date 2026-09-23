#!/usr/bin/env bash
set -euo pipefail

# Pull the source image into containerd's k8s.io namespace before seeding.
source_image='quay.io/prometheus/blackbox-exporter:v0.28.0'
registry='192.168.88.3:5000'
destination="${registry}/prometheus/blackbox-exporter:v0.28.0"
stage='seed.local/blackbox-exporter:v0.28.0'
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
