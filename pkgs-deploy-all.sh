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
    local name="${1:-}"
    local version="${2:-}"
    local versioned="${TARGET_ROOT}.${name}-${version}"

    if [ -n "$version" ] && [ -d "$versioned" ]; then
        printf '%s' "$versioned"
        return 0
    fi
    return 1
}

python3 - "$PKG_INDEX_FILE" "${CUR_DIR}/.ohloha/artifacts" "${OHOS_CPU}" "${OHOS_SDK_API_VERSION}" <<'PY' | while IFS=$'\t' read -r name version deps build_file; do
import json
import os
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    packages = json.load(f)

artifact_root = sys.argv[2]
arch = sys.argv[3]
ohos_api = sys.argv[4]
resolved_deps = {}

if os.path.isdir(artifact_root):
    for root, dirs, files in os.walk(artifact_root):
        if "manifest.json" not in files or "success" not in files:
            continue
        manifest_path = os.path.join(root, "manifest.json")
        try:
            with open(manifest_path, encoding="utf-8") as f:
                manifest = json.load(f)
        except Exception:
            continue
        if manifest.get("arch") != arch or str(manifest.get("ohos_api", "")) != str(ohos_api):
            continue
        deps = manifest.get("dependency_artifacts")
        if isinstance(deps, dict):
            resolved_deps[(manifest.get("name"), manifest.get("version"))] = ",".join(sorted(str(name) for name in deps))

for pkg in packages:
    name = pkg["name"]
    version = pkg["version"]
    deps = resolved_deps.get((name, version))
    if deps is None:
        deps = ",".join(pkg.get("deps", []))
    print(
        name,
        version,
        deps,
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

    resd=$(get_pkg_dst_dir "$name" "$version")
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
