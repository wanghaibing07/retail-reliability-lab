#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

NAMESPACE="retail"
ARGO_NAMESPACE="argocd"
APPLICATION="retail"
KUSTOMIZE_DIR="${ROOT_DIR}/infra/apps/retail"
TIMEOUT="${TIMEOUT:-180s}"

DRY_RUN=false
ASSUME_YES=false

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

usage() {
    cat <<USAGE
Usage:
  ./scripts/destroy.sh --dry-run
  ./scripts/destroy.sh
  ./scripts/destroy.sh --yes

Options:
  --dry-run   Show what would be deleted without changing the cluster.
  --yes       Skip interactive confirmation.
  -h, --help  Show this help.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            ;;
        --yes)
            ASSUME_YES=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "Unknown argument: $1"
            ;;
    esac
    shift
done

command -v kubectl >/dev/null 2>&1 ||
    fail "kubectl not found"

echo "=== Retail environment destroy ==="
echo "Application: ${ARGO_NAMESPACE}/${APPLICATION}"
echo "Namespace  : ${NAMESPACE}"
echo

APP_EXISTS=false
NS_EXISTS=false

if kubectl -n "${ARGO_NAMESPACE}" get application "${APPLICATION}" \
    >/dev/null 2>&1; then
    APP_EXISTS=true
fi

if kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
    NS_EXISTS=true
fi

if ! ${APP_EXISTS} && ! ${NS_EXISTS}; then
    echo "[PASS] Retail Application and namespace are already absent"
    exit 0
fi

# Refuse unexpected Argo deletion semantics.
if ${APP_EXISTS}; then
    FINALIZERS="$(
        kubectl -n "${ARGO_NAMESPACE}" \
            get application "${APPLICATION}" \
            -o jsonpath='{.metadata.finalizers}'
    )"

    if [[ -n "${FINALIZERS}" && "${FINALIZERS}" != "[]" ]]; then
        fail "Argo Application has finalizers: ${FINALIZERS}. Review deletion semantics first."
    fi
fi

# Warn when live StatefulSets use ephemeral emptyDir storage.
if ${NS_EXISTS}; then
    if ! LIVE_STATEFULSETS_YAML="$(
        kubectl get statefulsets             -n "${NAMESPACE}"             -o yaml
    )"; then
        fail "Unable to inspect live StatefulSets for ephemeral storage"
    fi

    if grep -qE '^[[:space:]]*(-[[:space:]]*)?emptyDir:'         <<< "${LIVE_STATEFULSETS_YAML}"; then
        echo "[WARN] Retail StatefulSets use emptyDir storage."
        echo "[WARN] MySQL/PostgreSQL/RabbitMQ data will be lost when the namespace is deleted."
        echo
    fi
fi

echo "Planned actions:"

if ${APP_EXISTS}; then
    echo "  1. Delete Argo Application ${ARGO_NAMESPACE}/${APPLICATION}"
    echo "     (non-cascading because no Argo resource finalizer is present)"
else
    echo "  1. Argo Application already absent"
fi

if ${NS_EXISTS}; then
    echo "  2. Delete namespace ${NAMESPACE}"
else
    echo "  2. Namespace already absent"
fi

echo

if ${DRY_RUN}; then
    echo "[PASS] Dry run only; no cluster resources were changed"
    exit 0
fi

if ! ${ASSUME_YES}; then
    if [[ ! -t 0 ]]; then
        fail "Interactive confirmation unavailable; use --yes explicitly"
    fi

    read -r -p "Type '${NAMESPACE}' to confirm destruction: " CONFIRM

    [[ "${CONFIRM}" == "${NAMESPACE}" ]] ||
        fail "Confirmation did not match; destroy cancelled"
fi

if ${APP_EXISTS}; then
    echo "[1/2] Stop Argo CD management"

    kubectl -n "${ARGO_NAMESPACE}" \
        delete application "${APPLICATION}" \
        --wait=true \
        --timeout="${TIMEOUT}"

    echo "[PASS] Argo Application removed"
else
    echo "[1/2] Argo Application already absent"
fi

if ${NS_EXISTS}; then
    echo "[2/2] Delete Retail namespace"

    kubectl delete namespace "${NAMESPACE}" \
        --wait=true \
        --timeout="${TIMEOUT}"

    echo "[PASS] Namespace ${NAMESPACE} removed"
else
    echo "[2/2] Namespace already absent"
fi

echo
echo "========================================"
echo "[PASS] Retail environment destroyed"
echo "========================================"
