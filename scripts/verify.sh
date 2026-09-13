#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

NAMESPACE="${NAMESPACE:-retail}"
TIMEOUT="${TIMEOUT:-300s}"
UI_SERVICE="${UI_SERVICE:-ui}"

EVIDENCE_DIR="${ROOT_DIR}/evidence"
mkdir -p "${EVIDENCE_DIR}"

TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
LOG_FILE="${EVIDENCE_DIR}/verify-${TIMESTAMP}.log"

exec > >(tee -a "${LOG_FILE}") 2>&1

echo "=== Retail deployment verification ==="
echo "Namespace: ${NAMESPACE}"
echo "Started  : $(date '+%F %T')"
echo

fail() {
    echo
    echo "[FAIL] $*"
    exit 1
}

pass() {
    echo "[PASS] $*"
}

# --------------------------------------------------
# 0. Preflight
# --------------------------------------------------

command -v kubectl >/dev/null 2>&1 ||
    fail "kubectl not found"

command -v curl >/dev/null 2>&1 ||
    fail "curl not found"

kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1 ||
    fail "Namespace ${NAMESPACE} does not exist"

pass "Kubernetes API and namespace are reachable"

# --------------------------------------------------
# 1. Workload verification
# --------------------------------------------------

echo
echo "=== Layer 1: Workloads ==="

mapfile -t WORKLOADS < <(
    kubectl get deployments,statefulsets \
        -n "${NAMESPACE}" \
        -o name
)

[[ ${#WORKLOADS[@]} -gt 0 ]] ||
    fail "No deployments/statefulsets found"

for workload in "${WORKLOADS[@]}"; do
    echo "[CHECK] ${workload}"

    kubectl rollout status \
        -n "${NAMESPACE}" \
        "${workload}" \
        --timeout="${TIMEOUT}"

    pass "${workload}"
done

echo
echo "[CHECK] All Pods Ready"

kubectl wait \
    --for=condition=Ready \
    pod \
    --all \
    -n "${NAMESPACE}" \
    --timeout="${TIMEOUT}"

pass "All Pods are Ready"

# --------------------------------------------------
# 2. Service / EndpointSlice verification
# --------------------------------------------------

echo
echo "=== Layer 2: Services ==="

mapfile -t SERVICES < <(
    kubectl get services \
        -n "${NAMESPACE}" \
        -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
)

for svc in "${SERVICES[@]}"; do

    # Ignore Services without selectors.
    SELECTOR="$(
        kubectl get service "${svc}" \
            -n "${NAMESPACE}" \
            -o jsonpath='{.spec.selector}' 2>/dev/null || true
    )"

    if [[ -z "${SELECTOR}" || "${SELECTOR}" == "map[]" ]]; then
        echo "[SKIP] ${svc}: no selector"
        continue
    fi

    READY_ENDPOINTS="$(
        kubectl get endpointslice \
            -n "${NAMESPACE}" \
            -l "kubernetes.io/service-name=${svc}" \
            -o jsonpath='{range .items[*].endpoints[?(@.conditions.ready==true)]}{.addresses[0]}{" "}{end}' \
            2>/dev/null || true
    )"

    if [[ -z "${READY_ENDPOINTS// }" ]]; then
        fail "Service ${svc} has no Ready Endpoint"
    fi

    echo "[OK] ${svc}: ${READY_ENDPOINTS}"
done

pass "All selected Services have Ready Endpoints"

# --------------------------------------------------
# 3. Business HTTP verification
# --------------------------------------------------

echo
echo "=== Layer 3: Business HTTP ==="

NODE_PORT="$(
    kubectl get service "${UI_SERVICE}" \
        -n "${NAMESPACE}" \
        -o jsonpath='{.spec.ports[0].nodePort}'
)"

[[ -n "${NODE_PORT}" ]] ||
    fail "${UI_SERVICE} Service has no NodePort"

NODE_IP="$(
    kubectl get nodes \
        -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}'
)"

[[ -n "${NODE_IP}" ]] ||
    fail "Unable to determine Kubernetes Node IP"

URL="http://${NODE_IP}:${NODE_PORT}/"

echo "[CHECK] ${URL}"

HTTP_CODE="$(
    curl \
        --silent \
        --show-error \
        --output /dev/null \
        --write-out '%{http_code}' \
        --connect-timeout 5 \
        --max-time 20 \
        "${URL}" || true
)"

if [[ ! "${HTTP_CODE}" =~ ^2[0-9][0-9]$ ]]; then
    fail "Business HTTP check failed: HTTP ${HTTP_CODE}"
fi

pass "Business HTTP check returned ${HTTP_CODE}"

# --------------------------------------------------
# 4. Save final evidence
# --------------------------------------------------

echo
echo "=== Evidence ==="

kubectl get pods \
    -n "${NAMESPACE}" \
    -o wide \
    > "${EVIDENCE_DIR}/verify-${TIMESTAMP}-pods.txt"

kubectl get services \
    -n "${NAMESPACE}" \
    -o wide \
    > "${EVIDENCE_DIR}/verify-${TIMESTAMP}-services.txt"

kubectl get endpointslice \
    -n "${NAMESPACE}" \
    -o wide \
    > "${EVIDENCE_DIR}/verify-${TIMESTAMP}-endpointslices.txt"

echo
echo "========================================"
echo "[PASS] Retail application verification succeeded"
echo "Finished: $(date '+%F %T')"
echo "Log     : ${LOG_FILE}"
echo "========================================"
