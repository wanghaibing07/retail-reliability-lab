#!/usr/bin/env bash
set -Eeuo pipefail

CHECKER="./scripts/check-image-tags.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

cat > "${TMP_DIR}/bad-normal.yaml" <<'YAML'
image: demo:latest
YAML

cat > "${TMP_DIR}/bad-list.yaml" <<'YAML'
- image: demo:latest
YAML

cat > "${TMP_DIR}/good.yaml" <<'YAML'
image: demo:v1
- image: demo:v2
YAML

expect_exit() {
    local expected="$1"
    local file="$2"
    local label="$3"
    local rc

    if "${CHECKER}" "${file}" >/dev/null 2>&1; then
        rc=0
    else
        rc=$?
    fi

    if [[ "${rc}" -ne "${expected}" ]]; then
        echo "[FAIL] ${label}: expected=${expected}, actual=${rc}"
        exit 1
    fi
}

expect_exit 1 "${TMP_DIR}/bad-normal.yaml" "normal latest"
expect_exit 1 "${TMP_DIR}/bad-list.yaml" "list latest"
expect_exit 0 "${TMP_DIR}/good.yaml" "valid tags"

echo "[PASS] image tag policy regression tests"
