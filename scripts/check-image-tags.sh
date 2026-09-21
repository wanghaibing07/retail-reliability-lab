#!/usr/bin/env bash
set -Eeuo pipefail

MANIFEST="${1:-}"

[[ -f "${MANIFEST}" ]] || {
    echo "[FAIL] manifest not found: ${MANIFEST}"
    exit 2
}

FOUND_LATEST=0

while IFS= read -r image; do
    if [[ "${image}" == *:latest ]]; then
        echo "[FAIL] latest image tag detected: ${image}"
        FOUND_LATEST=1
    fi
done < <(
    awk '
    /^[[:space:]]*(-[[:space:]]*)?image:/ {
        sub(/^[[:space:]]*(-[[:space:]]*)?image:[[:space:]]*/, "", $0)
        gsub(/^"|"$/, "", $0)
        print
    }
    ' "${MANIFEST}"
)

if (( FOUND_LATEST )); then
    exit 1
fi

echo "[PASS] No latest image tags"
