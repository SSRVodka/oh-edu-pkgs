#!/bin/bash

set -Eeuo pipefail

CUR_DIR=$(dirname "$(readlink -f "$0")")
cd "${CUR_DIR}"

PKG_SERVER=ohla-server
PKG_TOOL=ohla-tool

. setup2.sh

PKG_INDEX_FILE="${CUR_DIR}/PKG_INDEX.json"
./gen-pkg-index.sh

DEPLOY_DIR="${CUR_DIR}/deploy"
REPO_DIR="${CUR_DIR}/deploy/repo"
if [ ! -d "$REPO_DIR" ]; then
    mkdir -p "$REPO_DIR"
    "$PKG_SERVER" init --repo "$REPO_DIR"
fi

get_pkg_dst_dir() {
    printf '%s.%s' "${TARGET_ROOT}" "$1"
}

python3 - "$PKG_INDEX_FILE" <<'PY' | while IFS=$'\t' read -r name version deps build_file; do
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    packages = json.load(f)

for pkg in packages:
    print(
        pkg["name"],
        pkg["version"],
        ",".join(pkg.get("deps", [])),
        pkg["build_file"],
        sep="\t",
    )
PY
    echo "---- PKG ----"
    echo "name=$name"
    echo "version=$version"
    echo "deps=$deps"
    echo "build_file=$build_file"
    echo "-------------"

    resd=$(get_pkg_dst_dir "$name")
    if [ ! -d "${resd}" ]; then
        warn "cannot find package input for '$name': '$resd'"
        continue
    fi
    
    "$PKG_TOOL" --api "${OHOS_SDK_API_VERSION}" -a "${OHOS_CPU}" -n "$name" -i "${resd}" \
        -v "$version" -o "$DEPLOY_DIR" --depends "$deps" --no-archlib-isolation
    
done

# deploy to repo
find "$DEPLOY_DIR" -maxdepth 1 -name "*.json" | while read -r file; do
	name=$(basename "$file" .json)
	abs_dir=$(dirname "$(realpath "$file")")
	echo "deploying $abs_dir/$name -> $REPO_DIR"
	"$PKG_SERVER" deploy "$abs_dir/$name.pkg" "$abs_dir/$name.json" --repo "$REPO_DIR"
done
