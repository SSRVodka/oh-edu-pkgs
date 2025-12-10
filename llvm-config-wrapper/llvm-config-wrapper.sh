#!/bin/bash

. setup.sh

NATIVE_LLVM_CONFIG=${CUR_DIR}/llvm/native-build/bin/llvm-config
TARGET_LLVM_PREFIX=${TARGET_ROOT}.llvm

for arg in "$@"; do
    case "$arg" in
        --cflags|--cppflags|--cxxflags)
            # warn: use path of native headers
            native_options=$("$NATIVE_LLVM_CONFIG" "$arg")
            echo "$native_options -I${TARGET_LLVM_PREFIX}/include"
            ;;
        --ldflags)
            echo "-L${TARGET_LLVM_PREFIX}/${OHOS_LIBDIR}"
            ;;
        --bindir)
            echo "${TARGET_LLVM_PREFIX}/bin"
            ;;
        --cmakedir)
            echo "${TARGET_LLVM_PREFIX}/${OHOS_LIBDIR}/cmake/llvm"
            ;;
        --includedir)
            echo "${TARGET_LLVM_PREFIX}/include"
            ;;
        --libdir)
            echo "${TARGET_LLVM_PREFIX}/${OHOS_LIBDIR}"
            ;;
        --host-target)
            echo "${OHOS_CPU}-unknown-linux-ohos"
            ;;
        --libfiles)
            sn=""
	    libfiles_str="$($NATIVE_LLVM_CONFIG --libfiles)"
            for lib in $libfiles_str; do
                bn=$(basename $lib)
		pn=${TARGET_LLVM_PREFIX}/${OHOS_LIBDIR}/$bn
		if [ -z "$sn" ]; then
			sn=$pn
		else
			sn="$sn $pn"
		fi
            done
            echo "$sn"
            ;;
        --obj-root|--prefix)
            echo "${TARGET_LLVM_PREFIX}"
            ;;
        --libnames|--libs)
            "$NATIVE_LLVM_CONFIG" "$arg"
            ;;
        --ignore-libllvm|--link-shared|--link-static)
            # TODO
            error "$0: unsupported option '$arg'"
            exit 1
            ;;
        *)
            "$NATIVE_LLVM_CONFIG" "$arg"
            ;;
    esac
done


