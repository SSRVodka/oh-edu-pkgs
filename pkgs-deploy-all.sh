#!/bin/bash

set -Eeuo pipefail

CUR_DIR=$(dirname $(readlink -f $0))
cd ${CUR_DIR}

PKG_SERVER=ohla-server
PKG_TOOL=ohla-tool

. setup2.sh

RT_VERSION_INFO="VERSION"
if [ ! -f "$RT_VERSION_INFO" ]; then
    ./gen-versions.sh
fi

DEPLOY_DIR="${CUR_DIR}/deploy"
REPO_DIR="${CUR_DIR}/deploy/repo"
if [ ! -d $REPO_DIR ]; then
    mkdir -p $REPO_DIR
    $PKG_SERVER init --repo $REPO_DIR
fi

get_pkg_dst_dir() {
    printf '%s.%s' "${TARGET_ROOT}" "$1"
}

# Read file line by line
while IFS= read -r line; do
    # Skip empty lines and comments
    [ -z "$line" ] && continue
    case "$line" in
        \#*) continue ;;
    esac
    
    # Parse line: <name> <version> [dependencies] [build_dependencies]
    # Use tab or space as delimiter
    read -r name version deps build_deps <<< "$line"
    
    # Handle case where deps or build_deps might be empty
    if [ -z "$name" ] || [ -z "$version" ]; then
        echo "Warning: Skipping invalid line: $line"
        continue
    fi
    
    # Set defaults for optional fields
    deps="${deps:-}"
    build_deps="${build_deps:-}"
    
    echo "---- PKG ----"
    echo "name=$name"
    echo "version=$version"
    echo "deps=$deps"
    echo "build_deps=$build_deps"
    echo "-------------"

    resd=$(get_pkg_dst_dir $name)
    if [ ! -d "${resd}" ]; then
        warn "cannot find package input for '$name': '$resd'"
        continue
    fi
    
    $PKG_TOOL --api ${OHOS_SDK_API_VERSION} -a ${OHOS_CPU} -n $name -i ${resd} \
        -v $version -o $DEPLOY_DIR --depends "$build_deps" --no-archlib-isolation
    
done < "$RT_VERSION_INFO"

# deploy to repo
find $DEPLOY_DIR -maxdepth 1 -name "*.json" | while read file; do
	name=$(basename "$file" .json)
	abs_dir=$(dirname $(realpath "$file"))
	echo "deploying $abs_dir/$name -> $REPO_DIR"
	$PKG_SERVER deploy $abs_dir/$name.pkg $abs_dir/$name.json --repo $REPO_DIR
done


