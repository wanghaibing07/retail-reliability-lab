#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

KUSTOMIZE_DIR="${KUSTOMIZE_DIR:-${ROOT_DIR}/infra/apps/retail}"
NAMESPACE="retail"
TIMEOUT="${TIMEOUT:-600s}"
UI_SERVICE="${UI_SERVICE:-ui}"

EVIDENCE_DIR="${EVIDENCE_DIR:-${ROOT_DIR}/evidence}"
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

[[ -f "${KUSTOMIZE_DIR}/kustomization.yaml" ]] ||
    fail "Kustomization not found: ${KUSTOMIZE_DIR}"

if ! EXPECTED_RESOURCE_OUTPUT="$(
    kubectl apply         -k "${KUSTOMIZE_DIR}"         --dry-run=client         -o name
)"; then
    fail "Unable to render expected desired state"
fi

[[ -n "${EXPECTED_RESOURCE_OUTPUT}" ]] ||
    fail "Expected desired state is empty"

mapfile -t EXPECTED_RESOURCES <<< "${EXPECTED_RESOURCE_OUTPUT}"

mapfile -t EXPECTED_WORKLOADS < <(
    printf '%s\n' "${EXPECTED_RESOURCES[@]}" |
        grep -E '^(deployment\.apps|statefulset\.apps)/' || true
)

mapfile -t EXPECTED_SERVICES < <(
    printf '%s\n' "${EXPECTED_RESOURCES[@]}" |
        grep -E '^service/' || true
)

[[ ${#EXPECTED_WORKLOADS[@]} -gt 0 ]] ||
    fail "No expected Deployments/StatefulSets found"

[[ ${#EXPECTED_SERVICES[@]} -gt 0 ]] ||
    fail "No expected Services found"

kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1 ||
    fail "Namespace ${NAMESPACE} does not exist"

pass "Kubernetes API and namespace are reachable"
pass "Expected desired state: ${#EXPECTED_WORKLOADS[@]} workloads, ${#EXPECTED_SERVICES[@]} services"

# --------------------------------------------------
# 1. Workload verification
# --------------------------------------------------

echo
echo "=== Layer 1: Workloads ==="

for workload in "${EXPECTED_WORKLOADS[@]}"; do
    echo "[CHECK] ${workload}"

    if ! kubectl get         -n "${NAMESPACE}"         "${workload}"         >/dev/null; then
        fail "Expected workload is missing: ${workload}"
    fi

    if ! kubectl rollout status         -n "${NAMESPACE}"         "${workload}"         --timeout="${TIMEOUT}"; then
        fail "Workload rollout failed: ${workload}"
    fi

    pass "${workload}"
done

echo
echo "[CHECK] Active Pods Ready"

if ! ACTIVE_POD_OUTPUT="$(
    kubectl get pods         -n "${NAMESPACE}"         --field-selector='status.phase!=Succeeded,status.phase!=Failed'         -o name
)"; then
    fail "Unable to query active Pods"
fi

[[ -n "${ACTIVE_POD_OUTPUT}" ]] ||
    fail "No active Pods found"

mapfile -t ACTIVE_PODS <<< "${ACTIVE_POD_OUTPUT}"

if ! kubectl wait     -n "${NAMESPACE}"     --for=condition=Ready     --timeout="${TIMEOUT}"     "${ACTIVE_PODS[@]}"; then
    fail "One or more active Pods did not become Ready"
fi

pass "All active Pods are Ready"

if ! FAILED_POD_OUTPUT="$(
    kubectl get pods         -n "${NAMESPACE}"         --field-selector='status.phase=Failed'         -o name
)"; then
    fail "Unable to query Failed Pods"
fi

if [[ -n "${FAILED_POD_OUTPUT}" ]]; then
    echo "[INFO] Terminal Failed/Evicted Pods are excluded from readiness:"
    printf '%s\n' "${FAILED_POD_OUTPUT}"
fi

# --------------------------------------------------
# 2. Service / EndpointSlice verification
# --------------------------------------------------

echo
echo "=== Layer 2: Services ==="

for svc_ref in "${EXPECTED_SERVICES[@]}"; do
    svc="${svc_ref#service/}"

    echo "[CHECK] service/${svc}"

    if ! SELECTOR="$(
        kubectl get service "${svc}"             -n "${NAMESPACE}"             -o jsonpath='{.spec.selector}'
    )"; then
        fail "Expected Service is missing or unreadable: ${svc}"
    fi

    if [[ -z "${SELECTOR}" || "${SELECTOR}" == "map[]" ]]; then
        echo "[SKIP] ${svc}: no selector"
        continue
    fi

    if ! READY_ENDPOINTS="$(
        kubectl get endpointslice             -n "${NAMESPACE}"             -l "kubernetes.io/service-name=${svc}"             -o jsonpath='{range .items[*].endpoints[?(@.conditions.ready==true)]}{.addresses[0]}{" "}{end}'
    )"; then
        fail "Unable to query EndpointSlices for Service ${svc}"
    fi

    if [[ -z "${READY_ENDPOINTS// }" ]]; then
        fail "Service ${svc} has no Ready Endpoint"
    fi

    echo "[OK] ${svc}: ${READY_ENDPOINTS}"
done

pass "All expected selected Services have Ready Endpoints"

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
