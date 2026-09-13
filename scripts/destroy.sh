#!/usr/bin/env bash
set -Eeuo pipefail

NAMESPACE="${NAMESPACE:-retail}"

echo "=== Retail environment destroy ==="
echo "Namespace: ${NAMESPACE}"

if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
    echo "[INFO] Namespace ${NAMESPACE} does not exist"
    exit 0
fi

kubectl delete namespace "${NAMESPACE}"

echo "[WAIT] Waiting for namespace deletion..."

kubectl wait \
    --for=delete \
    namespace/"${NAMESPACE}" \
    --timeout=180s

echo "[PASS] Namespace ${NAMESPACE} removed"
