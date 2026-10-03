#!/usr/bin/env bash
set -euo pipefail

version='2.0.22'

source_repo='ghcr.io/wanghaibing07/retail-reliability-lab-artillery'
source_digest='sha256:302fb531cb18e3685eaa81858cee54750c268df111465386fdbe938918797756'
source="${source_repo}@${source_digest}"

registry='192.168.88.3:5000'
destination="${registry}/artilleryio/artillery:${version}"
stage="seed.local/stage7-artillery:${version}"

hosts_dir='/etc/containerd/certs.d'
registry_ca="${hosts_dir}/docker.io/ca.crt"

tmp_hosts="$(mktemp -d)"

cleanup() {
  sudo ctr -n k8s.io images rm "$stage" >/dev/null 2>&1 || true
  rm -rf "$tmp_hosts"
}
trap cleanup EXIT

mkdir -p "${tmp_hosts}/ghcr.io"

cat > "${tmp_hosts}/ghcr.io/hosts.toml" <<'TOML'
server = "https://ghcr.io"

[host."https://ghcr.io"]
  capabilities = ["pull", "resolve"]
TOML

printf 'SOURCE|%s\n' "$source"
printf 'DESTINATION|%s\n' "$destination"

printf 'PULL_BEGIN|%s\n' "$source"

sudo ctr -n k8s.io images pull \
  --hosts-dir "$tmp_hosts" \
  --platform linux/amd64 \
  "$source"

printf 'PULL_OK|%s\n' "$source"

sudo ctr -n k8s.io images rm "$stage" >/dev/null 2>&1 || true

printf 'CONVERT_BEGIN|%s\n' "$stage"

sudo ctr -n k8s.io images convert \
  --platform linux/amd64 \
  "$source" \
  "$stage"

printf 'PUSH_BEGIN|%s\n' "$destination"

sudo ctr -n k8s.io images push \
  --local \
  --hosts-dir "$hosts_dir" \
  --max-concurrent-uploaded-layers 1 \
  "$destination" \
  "$stage"

printf 'PUSH_OK|%s\n' "$destination"

manifest_digest="$(
  curl \
    --cacert "$registry_ca" \
    -fsSI \
    -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
    "https://${registry}/v2/artilleryio/artillery/manifests/${version}" |
  awk '
    BEGIN { IGNORECASE=1 }
    /^Docker-Content-Digest:/ {
      gsub("\r", "", $2)
      print $2
    }
  '
)"

printf 'INTERNAL_DIGEST|%s\n' "$manifest_digest"

if [[ "$manifest_digest" != "$source_digest" ]]; then
  printf 'ERROR|digest mismatch expected=%s actual=%s\n' \
    "$source_digest" "$manifest_digest" >&2
  exit 1
fi

printf 'DIGEST_VERIFY_OK|%s\n' "$manifest_digest"

sudo crictl rmi \
  "docker.io/artilleryio/artillery:${version}" \
  >/dev/null 2>&1 || true

printf 'CRI_VERIFY_BEGIN|docker.io/artilleryio/artillery:%s\n' "$version"

sudo crictl pull \
  "docker.io/artilleryio/artillery:${version}"

printf 'CRI_VERIFY_OK|docker.io/artilleryio/artillery:%s\n' "$version"

printf 'SEED_COMPLETE\n'
