#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${MANIFEST:-${ROOT_DIR}/infra/vendor/retail-v1.6.2.yaml}"
NAMESPACE="${NAMESPACE:-retail}"

echo "=== Retail deployment ==="
echo "Namespace: ${NAMESPACE}"
echo "Manifest : ${MANIFEST}"
echo

command -v kubectl >/dev/null 2>&1 || {
    echo "[FAIL] kubectl not found"
    exit 1
}

[[ -f "${MANIFEST}" ]] || {
    echo "[FAIL] Manifest not found: ${MANIFEST}"
    exit 1
}

echo "[1/4] Pre-pull images"
"${ROOT_DIR}/scripts/prepull-images.sh"

echo
echo "[2/4] Create namespace"
kubectl create namespace "${NAMESPACE}" \
    --dry-run=client \
    -o yaml | kubectl apply -f -

echo
echo "[3/4] Apply application"
kubectl apply \
    -n "${NAMESPACE}" \
    -f "${MANIFEST}"

echo
echo "[4/4] Verify application"
"${ROOT_DIR}/scripts/verify.sh"

echo
echo "========================================"
echo "[PASS] Retail deployment succeeded"
echo "========================================"
