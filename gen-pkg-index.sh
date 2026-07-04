#!/bin/bash
set -Eeuo pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
cd "${SCRIPT_DIR}"

INDEX_FILE="${SCRIPT_DIR}/PKG_INDEX.json"
TMP_FILE=$(mktemp "${INDEX_FILE}.tmp.XXXXXX")

cleanup() {
    rm -f "${TMP_FILE}"
}
trap cleanup EXIT

printf '[\n' > "${TMP_FILE}"

first=true
for build_file in "${SCRIPT_DIR}"/*/BUILD; do
    [ -f "${build_file}" ] || continue
    if [ "${first}" = true ]; then
        first=false
    else
        printf ',\n' >> "${TMP_FILE}"
    fi
    "${SCRIPT_DIR}/builder.sh" --print-meta "${build_file}" >> "${TMP_FILE}"
done

printf '\n]\n' >> "${TMP_FILE}"
mv "${TMP_FILE}" "${INDEX_FILE}"
trap - EXIT
