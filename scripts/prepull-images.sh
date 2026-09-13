#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${MANIFEST:-${ROOT_DIR}/infra/vendor/retail-v1.6.2.yaml}"
SSH_USER="${SSH_USER:-root}"

EVIDENCE_DIR="${ROOT_DIR}/evidence"
mkdir -p "${EVIDENCE_DIR}"

LOG_FILE="${EVIDENCE_DIR}/prepull-$(date '+%Y%m%d-%H%M%S').log"
exec > >(tee -a "${LOG_FILE}") 2>&1

echo "=== Retail image pre-pull ==="
echo "Manifest: ${MANIFEST}"
echo "Started : $(date '+%F %T')"
echo

# ---------- Preflight ----------

command -v kubectl >/dev/null 2>&1 || {
    echo "[FAIL] kubectl not found"
    exit 1
}

command -v ssh >/dev/null 2>&1 || {
    echo "[FAIL] ssh not found"
    exit 1
}

[[ -f "${MANIFEST}" ]] || {
    echo "[FAIL] Manifest not found: ${MANIFEST}"
    exit 1
}

# ---------- Extract images ----------

mapfile -t IMAGES < <(
    awk '
    /^[[:space:]]*image:/ {
        sub(/^[[:space:]]*image:[[:space:]]*/, "", $0)
        gsub(/^"|"$/, "", $0)
        print
    }
    ' "${MANIFEST}" | sort -u
)

if [[ ${#IMAGES[@]} -eq 0 ]]; then
    echo "[FAIL] No images found in manifest"
    exit 1
fi

echo "[INFO] Found ${#IMAGES[@]} unique images:"
printf '  - %s\n' "${IMAGES[@]}"
echo

# ---------- Discover workers ----------

mapfile -t NODES < <(
    kubectl get nodes --no-headers |
        awk '$3 !~ /(control-plane|master)/ {print $1}'
)

if [[ ${#NODES[@]} -eq 0 ]]; then
    echo "[FAIL] No worker nodes found"
    exit 1
fi

echo "[INFO] Worker nodes:"
printf '  - %s\n' "${NODES[@]}"
echo

# ---------- Check remote runtime ----------

for node in "${NODES[@]}"; do
    echo "[CHECK] ${node}: SSH + crictl"

    ssh \
        -o BatchMode=yes \
        -o ConnectTimeout=5 \
        "${SSH_USER}@${node}" \
        "command -v crictl >/dev/null"

    echo "[OK] ${node}"
done

echo

# ---------- Serial image pull ----------

TOTAL=$(( ${#NODES[@]} * ${#IMAGES[@]} ))
CURRENT=0

for node in "${NODES[@]}"; do
    echo "========================================"
    echo "[NODE] ${node}"
    echo "========================================"

    for image in "${IMAGES[@]}"; do
        CURRENT=$((CURRENT + 1))

        echo
        echo "[${CURRENT}/${TOTAL}] Pulling on ${node}"
        echo "[IMAGE] ${image}"
        # Image reference intentionally expands on the client side
        # from the version-locked manifest.
        # shellcheck disable=SC2029
        if ssh "${SSH_USER}@${node}" crictl pull "${image}"; then
            echo "[OK] ${node}: ${image}"
        else
            echo "[FAIL] ${node}: ${image}"
            echo "[FAIL] Pre-pull aborted."
            exit 1
        fi
    done
done

echo
echo "========================================"
echo "[PASS] All images are available on all workers"
echo "Finished: $(date '+%F %T')"
echo "Log: ${LOG_FILE}"
echo "========================================"
