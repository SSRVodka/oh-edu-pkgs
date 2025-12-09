#!/bin/bash

CUR_DIR=$(dirname $(readlink -f $0))
cd ${CUR_DIR}

. setup.sh

VERSIONS_INFO="VERSIONS"
DEPLOY_DIR="${CUR_DIR}/deploy"
REPO_DIR="${CUR_DIR}/deploy/repo"
if [ ! -d $REPO_DIR ]; then
	mkdir -p $REPO_DIR
	oh-pkgserver init --repo $REPO_DIR
fi

# Read file line by line
while IFS= read -r line; do
    # Skip empty lines and comments
    [ -z "$line" ] && continue
    case "$line" in
        \#*) continue ;;
    esac

    # Split the first three fields, keep the rest as deps
    set -- $line
    dir=$1
    name=$2
    version=$3
    shift 3
    deps="$*"

    echo "---- PKG ----"
    echo "dir=$dir"
    echo "name=$name"
    echo "version=$version"
    echo "deps=$deps"
    echo "-------------"

    arch_lib_isolation="--no-archlib-isolation"
    #if [ "$name" == "qt5" ]; then
    #    arch_lib_isolation="--no-archlib-isolation"
    #fi

    resd=${TARGET_ROOT}.${dir}
    if [ ! -d "$resd" ]; then
	    warn "cannot find package dir: $resd"
	    sleep 5
	    continue
    fi

    oh-pkgtool --api ${OHOS_SDK_API_VERSION} -a ${OHOS_CPU} -n $name -i ${resd} -v $version -o $DEPLOY_DIR --depends "$deps" $arch_lib_isolation

done < "$VERSIONS_INFO"

# deploy to repo
find $DEPLOY_DIR -maxdepth 1 -name "*.json" | while read file; do
	name=$(basename "$file" .json)
	abs_dir=$(dirname $(realpath "$file"))
	echo "deploying $abs_dir/$name -> $REPO_DIR"
	oh-pkgserver deploy $abs_dir/$name.pkg $abs_dir/$name.json --repo $REPO_DIR
done


