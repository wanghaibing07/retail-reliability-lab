#!/usr/bin/env bash
set -Eeuo pipefail

KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"
NAMESPACE="${NAMESPACE:-retail}"
PRODUCTION_SERVICE="${PRODUCTION_SERVICE:-orders-postgresql}"

BACKUP_FILE=""
RESTORE_POD=""
EXPECTED_SHA=""
MARKER_ID=""
LOG_FILE=""

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

usage() {
    cat <<'USAGE'
Usage:
  ./scripts/restore-orders.sh \
    --backup-file /path/to/orders.dump \
    --restore-pod orders-postgresql-restore-s5 \
    [--expected-sha SHA256] \
    [--marker-id ORDER_ID] \
    [--log-file /path/to/pg_restore.log]

Environment:
  KUBECONFIG          Defaults to /etc/kubernetes/admin.conf
  NAMESPACE           Defaults to retail
  PRODUCTION_SERVICE  Defaults to orders-postgresql

Safety:
  The target Pod must not be selected by the production PostgreSQL Service.
  The target public schema must contain zero tables before restore.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --backup-file)
            [[ $# -ge 2 ]] || fail "--backup-file requires a value"
            BACKUP_FILE="$2"
            shift 2
            ;;
        --restore-pod)
            [[ $# -ge 2 ]] || fail "--restore-pod requires a value"
            RESTORE_POD="$2"
            shift 2
            ;;
        --expected-sha)
            [[ $# -ge 2 ]] || fail "--expected-sha requires a value"
            EXPECTED_SHA="$2"
            shift 2
            ;;
        --marker-id)
            [[ $# -ge 2 ]] || fail "--marker-id requires a value"
            MARKER_ID="$2"
            shift 2
            ;;
        --log-file)
            [[ $# -ge 2 ]] || fail "--log-file requires a value"
            LOG_FILE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "unknown argument: $1"
            ;;
    esac
done

[[ -n "${BACKUP_FILE}" ]] || fail "--backup-file is required"
[[ -n "${RESTORE_POD}" ]] || fail "--restore-pod is required"
[[ -f "${BACKUP_FILE}" ]] || fail "backup file not found: ${BACKUP_FILE}"
[[ -s "${BACKUP_FILE}" ]] || fail "backup file is empty: ${BACKUP_FILE}"

for command in kubectl sha256sum awk date tee python3; do
    command -v "${command}" >/dev/null 2>&1 ||
        fail "required command not found: ${command}"
done

kubectl --kubeconfig="${KUBECONFIG}" -n "${NAMESPACE}"     get pod "${RESTORE_POD}" >/dev/null ||
    fail "restore Pod not found: ${NAMESPACE}/${RESTORE_POD}"

mapfile -t PRODUCTION_TARGETS < <(
    kubectl --kubeconfig="${KUBECONFIG}" -n "${NAMESPACE}" get endpointslice         -l "kubernetes.io/service-name=${PRODUCTION_SERVICE}"         -o jsonpath='{range .items[*].endpoints[*]}{.targetRef.name}{"\n"}{end}'
)

for target in "${PRODUCTION_TARGETS[@]}"; do
    [[ "${RESTORE_POD}" != "${target}" ]] ||
        fail "restore target is selected by production Service ${PRODUCTION_SERVICE}"
done

LOCAL_SHA="$(sha256sum "${BACKUP_FILE}" | awk '{print $1}')"

if [[ -n "${EXPECTED_SHA}" && "${LOCAL_SHA}" != "${EXPECTED_SHA}" ]]; then
    fail "backup checksum mismatch: expected ${EXPECTED_SHA}, got ${LOCAL_SHA}"
fi

REMOTE_FILE="/tmp/stage5-orders-restore-$(date -u +%Y%m%dT%H%M%SZ).dump"

if [[ -z "${LOG_FILE}" ]]; then
    LOG_FILE="./pg_restore-$(date -u +%Y%m%dT%H%M%SZ).log"
fi

mkdir -p "$(dirname "${LOG_FILE}")"

echo "=== Orders PostgreSQL isolated restore ==="
echo "backup_file  : ${BACKUP_FILE}"
echo "restore_pod  : ${NAMESPACE}/${RESTORE_POD}"
echo "backup_sha256: ${LOCAL_SHA}"
echo

kubectl --kubeconfig="${KUBECONFIG}" -n "${NAMESPACE}" exec -i     "${RESTORE_POD}" -c postgresql --     sh -c 'cat > "$1"' sh "${REMOTE_FILE}" < "${BACKUP_FILE}"

REMOTE_SHA="$(
    kubectl --kubeconfig="${KUBECONFIG}" -n "${NAMESPACE}" exec         "${RESTORE_POD}" -c postgresql --         sha256sum "${REMOTE_FILE}" |
        awk '{print $1}'
)"

[[ "${REMOTE_SHA}" == "${LOCAL_SHA}" ]] ||
    fail "restore Pod checksum mismatch"

kubectl --kubeconfig="${KUBECONFIG}" -n "${NAMESPACE}" exec     "${RESTORE_POD}" -c postgresql --     pg_restore --list "${REMOTE_FILE}" >/dev/null ||
    fail "pg_restore cannot read copied archive"

PUBLIC_TABLES="$(
    kubectl --kubeconfig="${KUBECONFIG}" -n "${NAMESPACE}" exec         "${RESTORE_POD}" -c postgresql --         sh -lc '
            psql -X -At                 -U "$POSTGRES_USER"                 -d "$POSTGRES_DB"                 -c "
                    SELECT count(*)
                    FROM pg_tables
                    WHERE schemaname = '''public''';
                "
        '
)"

[[ "${PUBLIC_TABLES}" == "0" ]] ||
    fail "restore target is not empty: public schema has ${PUBLIC_TABLES} table(s)"

RESTORE_STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)"
START_NS="$(date +%s%N)"

echo "restore_started_at=${RESTORE_STARTED_AT}" | tee "${LOG_FILE}"

if ! kubectl --kubeconfig="${KUBECONFIG}" -n "${NAMESPACE}" exec     "${RESTORE_POD}" -c postgresql --     sh -lc '
        pg_restore             --verbose             --exit-on-error             --single-transaction             --no-owner             --no-acl             -U "$POSTGRES_USER"             -d "$POSTGRES_DB"             "$1"
    ' sh "${REMOTE_FILE}" 2>&1 | tee -a "${LOG_FILE}"; then
    fail "pg_restore failed"
fi

DATABASE_RESTORE_COMPLETED_AT="$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)"
END_NS="$(date +%s%N)"

if [[ -n "${MARKER_ID}" ]]; then
    MARKER_COUNT="$(
        kubectl --kubeconfig="${KUBECONFIG}" -n "${NAMESPACE}" exec             "${RESTORE_POD}" -c postgresql --             sh -lc "
                psql -X -At                     -U \"\$POSTGRES_USER\"                     -d \"\$POSTGRES_DB\"                     -v ON_ERROR_STOP=1                     -c \"SELECT count(*) FROM orders WHERE id='${MARKER_ID}';\"
            "
    )"

    [[ "${MARKER_COUNT}" == "1" ]] ||
        fail "restore marker missing or duplicated: ${MARKER_ID}"
else
    MARKER_COUNT="not-checked"
fi

kubectl --kubeconfig="${KUBECONFIG}" -n "${NAMESPACE}" exec     "${RESTORE_POD}" -c postgresql --     rm -f "${REMOTE_FILE}"

DURATION="$(
    python3 - "${START_NS}" "${END_NS}" <<'PY'
import sys
start = int(sys.argv[1])
end = int(sys.argv[2])
print(f"{(end - start) / 1_000_000_000:.3f}")
PY
)"

{
    echo "database_restore_completed_at=${DATABASE_RESTORE_COMPLETED_AT}"
    echo "database_restore_seconds=${DURATION}"
    echo "marker_rows=${MARKER_COUNT}"
    echo "status=PASS"
} | tee -a "${LOG_FILE}"

echo
echo "=== RESTORE RESULT ==="
echo "backup_sha256=${LOCAL_SHA}"
echo "restore_pod=${RESTORE_POD}"
echo "database_restore_seconds=${DURATION}"
echo "marker_rows=${MARKER_COUNT}"
echo "pg_restore=PASS"
