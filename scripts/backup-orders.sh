#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"
NAMESPACE="${NAMESPACE:-retail}"
SOURCE_POD="${SOURCE_POD:-}"
BACKUP_ROOT="${BACKUP_ROOT:-/home/k8sadmin/retail-backups/orders}"
MARKER_ID="${MARKER_ID:-}"

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

for command in kubectl sha256sum stat python3 awk date git; do
    command -v "${command}" >/dev/null 2>&1 ||
        fail "required command not found: ${command}"
done

if [[ -z "${SOURCE_POD}" ]]; then
    mapfile -t SOURCE_PODS < <(
        kubectl --kubeconfig="${KUBECONFIG}" -n "${NAMESPACE}" get pod             -l 'app.kubernetes.io/name=orders,app.kubernetes.io/component=postgresql'             -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
    )

    [[ ${#SOURCE_PODS[@]} -eq 1 ]] ||
        fail "expected exactly one Orders PostgreSQL Pod, found ${#SOURCE_PODS[@]}"

    SOURCE_POD="${SOURCE_PODS[0]}"
fi

kubectl --kubeconfig="${KUBECONFIG}" -n "${NAMESPACE}"     get pod "${SOURCE_POD}" >/dev/null ||
    fail "source Pod not found: ${NAMESPACE}/${SOURCE_POD}"

POD_UID="$(
    kubectl --kubeconfig="${KUBECONFIG}" -n "${NAMESPACE}" get pod "${SOURCE_POD}"         -o jsonpath='{.metadata.uid}'
)"

SOURCE_NODE="$(
    kubectl --kubeconfig="${KUBECONFIG}" -n "${NAMESPACE}" get pod "${SOURCE_POD}"         -o jsonpath='{.spec.nodeName}'
)"

IMAGE="$(
    kubectl --kubeconfig="${KUBECONFIG}" -n "${NAMESPACE}" get pod "${SOURCE_POD}"         -o jsonpath='{.spec.containers[?(@.name=="postgresql")].image}'
)"

IMAGE_ID="$(
    kubectl --kubeconfig="${KUBECONFIG}" -n "${NAMESPACE}" get pod "${SOURCE_POD}"         -o jsonpath='{.status.containerStatuses[?(@.name=="postgresql")].imageID}'
)"

PG_VERSION="$(
    kubectl --kubeconfig="${KUBECONFIG}" -n "${NAMESPACE}" exec         "${SOURCE_POD}" -c postgresql --         sh -lc 'psql -X -At -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SHOW server_version;"'
)"

DB_NAME="$(
    kubectl --kubeconfig="${KUBECONFIG}" -n "${NAMESPACE}" exec         "${SOURCE_POD}" -c postgresql --         sh -lc 'printf "%s" "$POSTGRES_DB"'
)"

GIT_SHA="$(
    git -C "${ROOT_DIR}" rev-parse HEAD 2>/dev/null ||
        printf 'unknown'
)"

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_ID="${STAMP}-${POD_UID%%-*}"
OUT="${BACKUP_ROOT}/${BACKUP_ID}"

mkdir -p "${OUT}"
chmod 700 "${OUT}"

REMOTE_PARTIAL="/tmp/orders-${BACKUP_ID}.dump.partial"
LOCAL_PARTIAL="${OUT}/orders-${BACKUP_ID}.dump.partial"
FINAL="${OUT}/orders-${BACKUP_ID}.dump"
ARCHIVE_LIST="${OUT}/archive.list"
LOG="${OUT}/backup.log"
MANIFEST="${OUT}/manifest.json"
VALIDATION="${OUT}/validation.json"

STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
START_EPOCH="$(date +%s)"

{
    echo "backup_id=${BACKUP_ID}"
    echo "started_at=${STARTED_AT}"
    echo "original_database_node=${SOURCE_NODE}"
    echo "external_backup_host=$(hostname)"
} > "${LOG}"

echo "=== Orders PostgreSQL backup ==="
echo "backup_id             : ${BACKUP_ID}"
echo "source_pod            : ${NAMESPACE}/${SOURCE_POD}"
echo "original_database_node: ${SOURCE_NODE}"
echo "external_backup_host  : $(hostname)"
echo

kubectl --kubeconfig="${KUBECONFIG}" -n "${NAMESPACE}" exec     "${SOURCE_POD}" -c postgresql --     sh -lc '
        pg_dump             -U "$POSTGRES_USER"             -d "$POSTGRES_DB"             -Fc             -f "$1"
    ' sh "${REMOTE_PARTIAL}" 2>>"${LOG}"

kubectl --kubeconfig="${KUBECONFIG}" -n "${NAMESPACE}" exec     "${SOURCE_POD}" -c postgresql --     test -s "${REMOTE_PARTIAL}" ||
    fail "pg_dump produced an empty archive"

kubectl --kubeconfig="${KUBECONFIG}" -n "${NAMESPACE}" exec     "${SOURCE_POD}" -c postgresql --     pg_restore --list "${REMOTE_PARTIAL}" > "${ARCHIVE_LIST}" ||
    fail "pg_restore could not read the source archive"

REMOTE_SHA="$(
    kubectl --kubeconfig="${KUBECONFIG}" -n "${NAMESPACE}" exec         "${SOURCE_POD}" -c postgresql --         sha256sum "${REMOTE_PARTIAL}" |
        awk '{print $1}'
)"

kubectl --kubeconfig="${KUBECONFIG}" -n "${NAMESPACE}" exec     "${SOURCE_POD}" -c postgresql --     cat "${REMOTE_PARTIAL}" > "${LOCAL_PARTIAL}"

[[ -s "${LOCAL_PARTIAL}" ]] ||
    fail "external copy is empty"

LOCAL_SHA="$(sha256sum "${LOCAL_PARTIAL}" | awk '{print $1}')"

[[ "${LOCAL_SHA}" == "${REMOTE_SHA}" ]] ||
    fail "source/external SHA256 mismatch"

FILE_SIZE="$(stat -c '%s' "${LOCAL_PARTIAL}")"
COMPLETED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
END_EPOCH="$(date +%s)"
DURATION_SECONDS="$((END_EPOCH - START_EPOCH))"

export     BACKUP_ID STARTED_AT COMPLETED_AT DURATION_SECONDS     GIT_SHA SOURCE_POD POD_UID SOURCE_NODE IMAGE IMAGE_ID     PG_VERSION DB_NAME FILE_SIZE LOCAL_SHA FINAL MANIFEST VALIDATION MARKER_ID

python3 <<'PY'
import json
import os

manifest = {
    "backup_id": os.environ["BACKUP_ID"],
    "started_at": os.environ["STARTED_AT"],
    "completed_at": os.environ["COMPLETED_AT"],
    "duration_seconds": int(os.environ["DURATION_SECONDS"]),
    "git_sha": os.environ["GIT_SHA"],
    "source_pod": os.environ["SOURCE_POD"],
    "source_pod_uid": os.environ["POD_UID"],
    "original_database_node": os.environ["SOURCE_NODE"],
    "external_backup_host": os.uname().nodename,
    "postgres_version": os.environ["PG_VERSION"],
    "image": os.environ["IMAGE"],
    "image_id": os.environ["IMAGE_ID"],
    "database": os.environ["DB_NAME"],
    "dump_format": "custom",
    "file_size": int(os.environ["FILE_SIZE"]),
    "sha256": os.environ["LOCAL_SHA"],
    "external_copy_location": os.environ["FINAL"],
    "failure_domain": (
        "backup is outside the source database VM but remains on the same "
        "underlying VMware host"
    ),
    "validation_status": "passed",
}

validation = {
    "archive_nonempty": True,
    "pg_restore_list": "passed",
    "source_external_sha256_match": True,
    "sha256": os.environ["LOCAL_SHA"],
    "restore_marker_order_id": os.environ["MARKER_ID"] or None,
    "note": (
        "Archive structure and checksum are validated here. "
        "Recoverability requires a separate pg_restore into an isolated database."
    ),
}

for path, payload in (
    (os.environ["MANIFEST"], manifest),
    (os.environ["VALIDATION"], validation),
):
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")
PY

mv "${LOCAL_PARTIAL}" "${FINAL}"

kubectl --kubeconfig="${KUBECONFIG}" -n "${NAMESPACE}" exec     "${SOURCE_POD}" -c postgresql --     rm -f "${REMOTE_PARTIAL}"

{
    echo "completed_at=${COMPLETED_AT}"
    echo "duration_seconds=${DURATION_SECONDS}"
    echo "sha256=${LOCAL_SHA}"
    echo "status=PASS"
} >> "${LOG}"

echo
echo "=== BACKUP RESULT ==="
echo "backup_id=${BACKUP_ID}"
echo "original_database_node=${SOURCE_NODE}"
echo "external_backup_host=$(hostname)"
echo "file=${FINAL}"
echo "size_bytes=${FILE_SIZE}"
echo "sha256=${LOCAL_SHA}"
echo "duration_seconds=${DURATION_SECONDS}"
echo "archive_validation=PASS"
echo "external_sha_match=PASS"
