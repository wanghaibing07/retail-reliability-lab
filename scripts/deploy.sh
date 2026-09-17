#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUSTOMIZE_DIR="${KUSTOMIZE_DIR:-${ROOT_DIR}/infra/apps/retail}"
# Must match infra/apps/retail/kustomization.yaml
NAMESPACE="retail"

echo "=== Retail deployment ==="
echo "Namespace: ${NAMESPACE}"
echo "Kustomize: ${KUSTOMIZE_DIR}"
echo

command -v kubectl >/dev/null 2>&1 || {
    echo "[FAIL] kubectl not found"
    exit 1
}

[[ -f "${KUSTOMIZE_DIR}/kustomization.yaml" ]] || {
    echo "[FAIL] Kustomization not found: ${KUSTOMIZE_DIR}"
    exit 1
}

kubectl kustomize "${KUSTOMIZE_DIR}" >/dev/null || {
    echo "[FAIL] Unable to render Kustomize desired state"
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
kubectl apply -k "${KUSTOMIZE_DIR}"

echo
echo "[4/4] Verify application"
"${ROOT_DIR}/scripts/verify.sh"

echo
echo "========================================"
echo "[PASS] Retail deployment succeeded"
echo "========================================"
