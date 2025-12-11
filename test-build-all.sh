#!/bin/bash

set -Eeuo pipefail

cd $(dirname $(readlink -f $0))

. test-deps.sh

BUILDER=""

for dep in "${all_deps[@]}"; do
	BUILDER="$BUILDER $dep/BUILD"
done

./builder.sh $BUILDER

