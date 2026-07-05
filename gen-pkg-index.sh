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
while IFS= read -r build_file; do
    [ -f "${build_file}" ] || continue
    if [ "${first}" = true ]; then
        first=false
    else
        printf ',\n' >> "${TMP_FILE}"
    fi
    "${SCRIPT_DIR}/builder.sh" --print-meta "${build_file}" >> "${TMP_FILE}"
done < <(
    {
        find "${SCRIPT_DIR}" -mindepth 2 -maxdepth 2 -name BUILD -type f ! -path "${SCRIPT_DIR}/.*/*" -print
        find "${SCRIPT_DIR}" -mindepth 4 -maxdepth 4 -path "${SCRIPT_DIR}/*/versions/*/BUILD" -type f ! -path "${SCRIPT_DIR}/.*/*" -print
    } | sort -u
)

printf '\n]\n' >> "${TMP_FILE}"
mv "${TMP_FILE}" "${INDEX_FILE}"
trap - EXIT
