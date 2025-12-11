#!/bin/bash
set -Eeuo pipefail

CUR_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
cd $CUR_DIR

info () { printf "%b%s%b" "\E[1;34m❯ \E[1;36m" "${1:-}" "\E[0m\n"; }
error () { printf "%b%s%b" "\E[1;31m❯ " "ERROR: ${1:-}" "\E[0m\n" >&2; }
warn () { printf "%b%s%b" "\E[1;33m❯ " "Warning: ${1:-}" "\E[0m\n" >&2; }


OLD_PATH=$PATH
OLD_LD_LIBPATH=${LD_LIBRARY_PATH:=""}

trap "export PATH=${OLD_PATH}; export LD_LIBRARY_PATH=${OLD_LD_LIBPATH}; unset CC CXX AS LD LDXX LLD STRIP RANLIB OBJDUMP OBJCOPY READELF NM AR PROFDATA CFLAGS CXXFLAGS CPPFLAGS LDFLAGS LDSHARED PKG_CONFIG_PATH PKG_CONFIG_LIBDIR PKG_CONFIG_SYSTEM_IGNORE_PATH" ERR SIGINT SIGTERM

if [ -z "${OHOS_SDK:-}" ]; then
	warn "please set OHOS_SDK env first"
	exit 0
fi
OHOS_SDK_API_VERSION=$(cat ${OHOS_SDK}/toolchains/oh-uni-package.json | grep "apiVersion" | tr -d [:space:] | awk -F':' '{print $2}' | awk -F'"' '{print $2}')

BUILD_PLATFORM_TRIPLET=x86_64-pc-linux-gnu

CMAKE_BIN=${OHOS_SDK}/native/build-tools/cmake/bin/cmake
#CMAKE_TOOLCHAIN_CONFIG=${OHOS_SDK}/native/build/cmake/ohos.toolchain.cmake
CMAKE_TOOLCHAIN_CONFIG=${CUR_DIR}/cmake/ohos.toolchain.xhw.cmake

if [ -z "${OHOS_CPU:-}" ] || [ -z "${OHOS_ARCH:-}" ]; then
info "OHOS_CPU/OHOS_ARCH not specify: use aarch64 by default"
OHOS_CPU=aarch64
OHOS_ARCH=arm64-v8a
# OHOS_CPU=arm
# OHOS_ARCH=armeabi-v7a
# OHOS_CPU=x86_64
# OHOS_ARCH=x86_64
fi

ARCH=${OHOS_ARCH}

SRC_ROOT=${CUR_DIR}/.staging
mkdir -p ${SRC_ROOT}
TARGET_ROOT=${CUR_DIR}/dist.${OHOS_CPU}
TEST_DIR=${CUR_DIR}/test-only

PATCH_FILE_ROOT=${CUR_DIR}/patches

# export for cmake toolchain file
export OHOS_LIBDIR=lib
# Set this for OHOS sdk installation
# export OHOS_LIBDIR=lib/${OHOS_CPU}-linux-ohos

# NOTE: We no longer need gfortran for OpenBLAS
## Note: Fortran compiler should be changed with ARCH
## Use gnu here instead of ohos: code gen only
#FC=${OHOS_CPU}-linux-gnu-gfortran-11
#mkdir -p ${TARGET_ROOT}/${OHOS_LIBDIR}
#if [ ! -d ${CUR_DIR}/gfortran.libs.${OHOS_CPU} ]; then
#    warn "cannot find library gfortran.libs.${OHOS_CPU} in ${CUR_DIR}"
#else
#    #cp ${CUR_DIR}/gfortran.libs.${OHOS_CPU}/* ${TARGET_ROOT}/${OHOS_LIBDIR}
#    warn "skipping gfortran libs for open source license"
#fi


HOST_SYSROOT=${OHOS_SDK}/native/sysroot
HOST_LIBC=${HOST_SYSROOT}/usr/lib/${OHOS_CPU}-linux-ohos/libc.so

export CC="${OHOS_SDK}/native/llvm/bin/clang --target=${OHOS_CPU}-linux-ohos"
export CXX="${OHOS_SDK}/native/llvm/bin/clang++ --target=${OHOS_CPU}-linux-ohos"
export AS=${OHOS_SDK}/native/llvm/bin/llvm-as
export LD=${OHOS_SDK}/native/llvm/bin/ld.lld
export LDXX=${LD}
export LLD=${LD}
export STRIP=${OHOS_SDK}/native/llvm/bin/llvm-strip
# let `install` to use toolchain's strip
if [ ! -f ${OHOS_SDK}/native/llvm/bin/strip ]; then
	pushd ${OHOS_SDK}/native/llvm/bin
	ln -s llvm-strip strip
	popd
fi
export RANLIB=${OHOS_SDK}/native/llvm/bin/llvm-ranlib
export OBJDUMP=${OHOS_SDK}/native/llvm/bin/llvm-objdump
export OBJCOPY=${OHOS_SDK}/native/llvm/bin/llvm-objcopy
export READELF=${OHOS_SDK}/native/llvm/bin/llvm-readelf
export NM=${OHOS_SDK}/native/llvm/bin/llvm-nm
export AR=${OHOS_SDK}/native/llvm/bin/llvm-ar
export PROFDATA=${OHOS_SDK}/native/llvm/bin/llvm-profdata
if [ ! -f ${OHOS_SDK}/native/llvm/bin/profdata ]; then
	pushd ${OHOS_SDK}/native/llvm/bin
	ln -s llvm-profdata profdata
	popd
fi
#export CFLAGS="-fPIC -D__MUSL__=1 -D__OPENHARMONY__=1 -I${TARGET_ROOT}/include -I${TARGET_ROOT}/include/lzma -I${TARGET_ROOT}/include/ncursesw -I${TARGET_ROOT}/include/readline -I${TARGET_ROOT}/ssl/include"
# keep track with ohos.toolchain.cmake + CMAKE_C_FLAGS_INIT
# including arch-dependent headers
export CFLAGS="-fPIC -D__MUSL__ -D__OHOS__ -D__OPENHARMONY__ -Wno-shorten-64-to-32 -Wno-unused-command-line-argument -I${TARGET_ROOT}/include -I${HOST_SYSROOT}/usr/include -I${HOST_SYSROOT}/usr/include/${OHOS_CPU}-linux-ohos"
export CXXFLAGS=${CFLAGS}
export CPPFLAGS=${CXXFLAGS}
#export LDFLAGS="-fuse-ld=lld -L${TARGET_ROOT}/lib -L${TARGET_ROOT}/ssl/lib64 -L${CUR_DIR}/gfortran.libs.${OHOS_CPU}"
export LDFLAGS="-fuse-ld=lld -lm -L${TARGET_ROOT}/lib -L${HOST_SYSROOT}/usr/${OHOS_LIBDIR}"
export LDSHARED="${CC} ${LDFLAGS} -shared"

export PATH=${OHOS_SDK}/native/llvm/bin:${OHOS_SDK}/native/toolchains:$PATH

export PKG_CONFIG_SYSTEM_IGNORE_PATH=/usr/local/lib/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig
export PKG_CONFIG_LIBDIR="${HOST_SYSROOT}/usr/${OHOS_LIBDIR}:${HOST_SYSROOT}/usr/${OHOS_LIBDIR}/pkgconfig"
# export PKG_CONFIG_SYSROOT_DIR=${HOST_SYSROOT}


################################# Helpers #################################

compare_versions() {
	local v1="$1"
	local v2="$2"
	local max_version=$(echo -e "$v1\n$v2" | sort -Vr | head -n1)
	
	if [[ "$v1" == "$max_version" ]]; then
		if [[ "$v2" == "$max_version" ]]; then
			# version equal
			echo 0
		else
			# v1 is greater
			echo 1
		fi
	else
		# v2 is greater
		echo -1
	fi
}

replace_textline_with() {
	local old=$1
	local new=$2
	local target_file=$3
	if [ ! -f "$target_file" ]; then
		error "not a regular file: '$target_file'"
		return 1
	fi
	awk -v old="$old" -v new="$new" \
		'function trim(s){ sub(/^[ \t]+/,"",s); sub(/[ \t]+$/,"",s); return s }
		{ if (trim($0)==old) print new; else print }' $target_file > $target_file.tmp && mv $target_file.tmp $target_file
}

supports_all_options() {
	local prog="$1"
	shift
	local options=("$@")

	if [ ! -x "$prog" ]; then
		return 1
	fi

	if [ ${#options[@]} -eq 0 ]; then
		return 1
	fi

	local option
	for option in "${options[@]}"; do
		# check configure file itself
		# grep options:
		#   -F: no regex (fixed string)
		#   -q: quiet mode (no stdout result)
		#   -w: whole word match (-h not match --help)
		#   --: mark the end of options for grep (avoid regarding contents start with '-' as parameters)
		if ! grep -Fq -- "$option" "$prog"; then
			# check --help
			help_output="$("$prog" --help 2>&1 || :)"
			local exit_code=$?
			if [ "$exit_code" -ne 0 ]; then
				return 1
			fi
			if ! echo "$help_output" | grep -Fq -- "$option"; then
				return 1
			fi
		fi
	done

	return 0
}

build_makeproj_with_deps() {
	local target_dir="$1"
	local deps="${2:-}"
	local extra_configure_flags="${3:-}"
	# executing just before configure
	local bootstrap_script="${4:-}"
	local suffix_configure_flags="${5:-}"
	local make_parallism="${6:-}"
	local configure_dir="${7:-${target_dir}}"

	local OLD_CFLAGS="$CFLAGS"
	local OLD_CXXFLAGS="$CXXFLAGS"
	local OLD_CPPFLAGS="$CPPFLAGS"
	local OLD_LDFLAGS="$LDFLAGS"
	local OLD_PKG_CONFIG_LIBDIR="$PKG_CONFIG_LIBDIR"

	pushd "$configure_dir"

	local dep
	for dep in $deps; do
		CFLAGS="-I${TARGET_ROOT}.${dep}/include ${CFLAGS}"
		LDFLAGS="-L${TARGET_ROOT}.${dep}/${OHOS_LIBDIR} ${LDFLAGS}"
		PKG_CONFIG_LIBDIR="${TARGET_ROOT}.${dep}/${OHOS_LIBDIR}/pkgconfig:$PKG_CONFIG_LIBDIR"
	done

	CXXFLAGS="$CFLAGS"
	CPPFLAGS="$CFLAGS"

	if [ -n "$bootstrap_script" ] && [ -f "$bootstrap_script" ]; then
		bash "$bootstrap_script"
	fi

	local try_configure_exe="./configure ./Configure ./autogen.sh"
	local configure_exe=""
	for conf_exe in $try_configure_exe; do
		if [ -x "$conf_exe" ]; then
			configure_exe="$conf_exe"
			break
		fi
	done
	if [ -z "$configure_exe" ]; then
		error "no executable configure file in this project"
		return 1
	fi

	configure_flags="${extra_configure_flags} --prefix=${TARGET_ROOT}"
	configure_flags="${configure_flags} --libdir=${TARGET_ROOT}/${OHOS_LIBDIR}"

	if ! supports_all_options $configure_exe "--prefix" "--libdir"; then
		warn "configure file for ${target_dir} doesn't support --prefix/--libdir? It may cause some problems... Remember to check output directory afterwards :("
		#return 1
	fi
	if ! supports_all_options $configure_exe "--host"; then
		warn "configure file doesn't support --host. Take care of your CC/CXX environment variables!"
	else
		configure_flags="${configure_flags} --host=${OHOS_CPU}-linux-musl --build=${BUILD_PLATFORM_TRIPLET}"

		# optional
		if supports_all_options $configure_exe "--target"; then
			configure_flags="${configure_flags} --target=${OHOS_CPU}-linux-musl"
		fi
	fi

	# append suffix flags
	configure_flags="${configure_flags} ${suffix_configure_flags}"

	info "configure flags: ${configure_flags}"
	info "cflags: ${CFLAGS}"
	info "ldflags: ${LDFLAGS}"
	info "pkgconfig_libdir: ${PKG_CONFIG_LIBDIR}"
	$configure_exe $configure_flags

	#read -p "check >>> "
	make -j${make_parallism} || { return 1; }
	#read -p "check >>> "
	make install || { return 1; }

	CFLAGS="$OLD_CFLAGS"
	CXXFLAGS="$OLD_CXXFLAGS"
	CPPFLAGS="$OLD_CPPFLAGS"
	LDFLAGS="$OLD_LDFLAGS"
	PKG_CONFIG_LIBDIR="$OLD_PKG_CONFIG_LIBDIR"

	popd
	if [ -d ${TARGET_ROOT}.${target_dir} ]; then
		# merge directory
		cp -r ${TARGET_ROOT}/* ${TARGET_ROOT}.${target_dir}/
		rm -rf ${TARGET_ROOT}
	else
		mv ${TARGET_ROOT} ${TARGET_ROOT}.${target_dir}
	fi
	local dst_dir=${TARGET_ROOT}.${target_dir}/${OHOS_LIBDIR}
	if [ ! -d "$dst_dir" ]; then
		warn "library '$target_dir' doesn't have an arch-dependent library directory '$dst_dir'"
	else
		patch_libdir_origin $target_dir
	fi
	# some package configs may locate in share/: like xorg, asio (header-only)
	sharedir=${TARGET_ROOT}.${target_dir}/share
	if [ -d $sharedir ]; then
		patch_libdir_origin $target_dir "" "" "${TARGET_ROOT}.${target_dir}/share"
	fi
}

build_cmakeproj_with_deps() {
	local target_dir=$1
	local deps=${2:-}
	local _my_cmake_extra_flags=${3:-}
	local _my_extra_cmake_prefix=${4-}
	local _my_extra_cflags=${5:-}
	local _my_extra_cppflags=${6:-}
	local _my_extra_ldflags=${7:-}
	local parallism=${8:-}
	local _my_extra_cmake_findroot=${9:-}
	local _my_cmake_builddir=${10:-ohos-build}


	pushd $target_dir

	local dep
	local _extra_cflags=""
	local _extra_ldflags=""
	local _extra_cmakeprefix=""
	local _extra_cmakefindroot="$_my_extra_cmake_findroot"
	local OLD_PKG_CONFIG_LIBDIR="$PKG_CONFIG_LIBDIR"
	for dep in $deps; do
		_extra_cflags="-I${TARGET_ROOT}.${dep}/include ${_extra_cflags}"
		_extra_ldflags="-L${TARGET_ROOT}.${dep}/${OHOS_LIBDIR} ${_extra_ldflags}"
		local _tmp_cmakedir="${TARGET_ROOT}.${dep}/${OHOS_LIBDIR}/cmake"
		if [ -d "$_tmp_cmakedir" ]; then
			# non-recursive
			for _item in "$_tmp_cmakedir"/*; do
				if [ ! -e "$_item" ]; then
					continue
				fi
				_extra_cmakeprefix="$_item;${_extra_cmakeprefix}"
			done
		fi
		_extra_cmakefindroot="${TARGET_ROOT}.${dep};${_extra_cmakefindroot}"
		PKG_CONFIG_LIBDIR="${TARGET_ROOT}.${dep}/${OHOS_LIBDIR}/pkgconfig:$PKG_CONFIG_LIBDIR"
	done

	info "common c flags appended: $_extra_cflags $_my_extra_cflags"
	info "common link flags appended: $_extra_ldflags $_my_extra_ldflags"
	info "cmake prefix appended: $_extra_cmakeprefix;$_my_extra_cmake_prefix"
	info "pkgconfig libdir: $PKG_CONFIG_LIBDIR"

	# Use SSRVODKA_APPEND_CMAKE_PREFIX_PATH with semicolons
	${CMAKE_BIN} \
		${_my_cmake_extra_flags} \
		-DOHOS_ARCH=${OHOS_ARCH} \
		-DSSRVODKA_APPEND_COMMON_CFLAGS="$_extra_cflags $_my_extra_cflags" \
		-DSSRVODKA_APPEND_COMMON_LINK_FLAGS="$_extra_ldflags $_my_extra_ldflags" \
		-DSSRVODKA_APPEND_CMAKE_PREFIX_PATH="$_extra_cmakeprefix;$_my_extra_cmake_prefix" \
		-DSSRVODKA_APPEND_C_PREPROCESSOR_FLAGS="$_my_extra_cppflags" \
		-DSSRVODKA_APPEND_CMAKE_FIND_ROOT_PATH="$_extra_cmakefindroot" \
		-DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_CONFIG} \
		-DCMAKE_INSTALL_PREFIX=${TARGET_ROOT}.${target_dir} \
		-DCMAKE_INSTALL_LIBDIR=${OHOS_LIBDIR} \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_VERBOSE_MAKEFILE=ON \
		-DCMAKE_CROSSCOMPILING=ON \
		-B ${_my_cmake_builddir} || { return 1; }

	#read -p "Check >>> "
	${CMAKE_BIN} --build ${_my_cmake_builddir} -j${parallism} || { return 1; }
	${CMAKE_BIN} --install ${_my_cmake_builddir} || { return 1; }

	PKG_CONFIG_LIBDIR="$OLD_PKG_CONFIG_LIBDIR"
	popd

	local dst_archlibdir=${TARGET_ROOT}.${target_dir}/${OHOS_LIBDIR}
	if [ ! -d "$dst_archlibdir" ]; then
		warn "library '$target_dir' doesn't have an arch-dependent library directory '$dst_archlibdir'"
	else
		patch_libdir_origin $target_dir
	fi
	# some package configs may locate in share/: like xorg, asio (header-only)
	sharedir=${TARGET_ROOT}.${target_dir}/share
	if [ -d $sharedir ]; then
		patch_libdir_origin $target_dir "" "" "${TARGET_ROOT}.${target_dir}/share"
	fi
}

build_mesonproj_with_deps() {
	local target_dir=$1
	local deps=${2:-}
	local meson_cross_file=${3:-}
	local _my_extra_meson_flags=${4:-}
	local parallism=${5:-20}
	local _my_extra_cflags=${6:-}
	local _my_extra_ldflags=${7:-}
	local _my_extra_cmake_prefix=${8-}
	local _my_extra_cmake_findroot=${9:-}
	local _my_meson_builddir=${10:-ohos-build}

	pushd $target_dir
	mkdir -p $_my_meson_builddir
	pushd $_my_meson_builddir

	local dep
	local _extra_cflags=""
	local _extra_ldflags=""
	local _extra_cmakeprefix=""
	local _extra_cmakefindroot="$_my_extra_cmake_findroot"
	local OLD_PKG_CONFIG_LIBDIR="$PKG_CONFIG_LIBDIR"
	for dep in $deps; do
		_extra_cflags="-I${TARGET_ROOT}.${dep}/include ${_extra_cflags}"
		_extra_ldflags="-L${TARGET_ROOT}.${dep}/${OHOS_LIBDIR} ${_extra_ldflags}"
		local _tmp_cmakedir="${TARGET_ROOT}.${dep}/${OHOS_LIBDIR}/cmake"
		if [ -d "$_tmp_cmakedir" ]; then
			# non-recursive
			for _item in "$_tmp_cmakedir"/*; do
				if [ ! -e "$_item" ]; then
					continue
				fi
				_extra_cmakeprefix="$_item;${_extra_cmakeprefix}"
			done
		fi
		_extra_cmakefindroot="${TARGET_ROOT}.${dep};${_extra_cmakefindroot}"
		PKG_CONFIG_LIBDIR="${TARGET_ROOT}.${dep}/${OHOS_LIBDIR}/pkgconfig:$PKG_CONFIG_LIBDIR"
	done

	info "pkgconfig libdir: ${PKG_CONFIG_LIBDIR}"
	info "pkgconfig SYS IGNORE: ${PKG_CONFIG_SYSTEM_IGNORE_PATH}"

	# build flags for CMake (if use)
	sed -i -e "s|^\(SSRVODKA_APPEND_COMMON_CFLAGS[[:space:]]*=[[:space:]]*\).*|\1'$_extra_cflags $_my_extra_cflags'|" \
		-e "s|^\(SSRVODKA_APPEND_COMMON_LINK_FLAGS[[:space:]]*=[[:space:]]*\).*|\1'$_extra_ldflags $_my_extra_ldflags'|" \
		-e "s|^\(SSRVODKA_APPEND_CMAKE_PREFIX_PATH[[:space:]]*=[[:space:]]*\).*|\1'$_extra_cmakeprefix;$_my_extra_cmake_prefix'|" \
		-e "s|^\(SSRVODKA_APPEND_CMAKE_FIND_ROOT_PATH[[:space:]]*=[[:space:]]*\).*|\1'$_extra_cmakefindroot'|" \
		$meson_cross_file
	
	# flags for meson projects that are not using cmake
	set_meson_list "$meson_cross_file" "common_c_flags" "$CFLAGS $_extra_cflags $_my_extra_cflags"
	set_meson_list "$meson_cross_file" "common_ld_flags" "$LDFLAGS $_extra_ldflags $_my_extra_ldflags"

	meson setup --reconfigure \
		--cross-file=$meson_cross_file \
		--prefix=${TARGET_ROOT}.${target_dir} \
		--libdir=${OHOS_LIBDIR} \
		--buildtype=release \
		${_my_extra_meson_flags} \
		.. \
	|| { return 1; }
	# read -p "check >>> "
	ninja -v -j${parallism} || { return 1; }
	ninja install || { return 1; }

	PKG_CONFIG_LIBDIR="$OLD_PKG_CONFIG_LIBDIR"
	popd
	popd

	local dst_archlibdir=${TARGET_ROOT}.${target_dir}/${OHOS_LIBDIR}
	if [ ! -d "$dst_archlibdir" ]; then
		warn "library '$target_dir' doesn't have an arch-dependent library directory '$dst_archlibdir'"
	else
		patch_libdir_origin $target_dir
	fi
	# some package configs may locate in share/: like xorg, asio (header-only)
	sharedir=${TARGET_ROOT}.${target_dir}/share
	if [ -d $sharedir ]; then
		patch_libdir_origin $target_dir "" "" "${TARGET_ROOT}.${target_dir}/share"
	fi
}

# keep track with oh-pkgmgr install
patch_libdir_origin() {
	local target_dir=$1
	# for libraries like Python
	local skip_patch_so=${2:-}
	local dst_prefix=${3:-}
	local dst_archlib_dir_override=${4:-}

	if [ -z "$dst_prefix" ]; then
		dst_prefix=${TARGET_ROOT}.${target_dir}
	fi
	local dst_archlib_dir=${dst_prefix}/${OHOS_LIBDIR}
	if [ -n "$dst_archlib_dir_override" ]; then
		dst_archlib_dir=$dst_archlib_dir_override
	fi
	if [ ! -d "$dst_archlib_dir" ]; then
		error "cannot find directory '$dst_archlib_dir'"
		return 1
	fi
	# don't forget to patch *.la for libtool
	for la_file in "$dst_archlib_dir"/*.la; do
		if [ -f "$la_file" ]; then
			info "patching library archive file generated by libtool: $la_file"
			sed -i "s|libdir='.*'|libdir='${dst_archlib_dir}'|g" "$la_file"
		fi
	done
	# and patch *.pc for pkg-config
	for pc_file in "$dst_archlib_dir"/pkgconfig/*.pc; do
		if [ -f "$pc_file" ]; then
			info "patching pkg-config file generated by Makefile: $pc_file"
			sed -i -e "s|^prefix=.*|prefix=${dst_prefix}|g" \
				-e "s|^libdir=.*|libdir=${dst_archlib_dir}|g" \
				-e "\|^includedir=\${prefix}|! s|\(includedir=\).*\(/include.*\)$|\1${dst_prefix}\2|g" \
				"$pc_file"
		fi
	done
	# and patch so if necessary
	if [ -n "$skip_patch_so" ]; then
		info "skip patching shared objects"
		return 0
	fi
	for file in "$dst_archlib_dir"/*; do
		if [ -f "$file" ]; then
			if file "$file" | grep -q "ELF.*shared object"; then
				info "patching shared object: $file"
				patchelf --set-rpath '$ORIGIN' "$file"
			fi
		fi
	done
}


################################# Python Relative Local Envs #################################

# NOTE: you also need to change download-python.sh if you change this
PY_VERSION=3.12
PY_VERSION_CODE=312

# keep track with build-python.sh
PY_DEPS="libz openssl libffi sqlite bzip2 xz libncursesw libreadline libgettext util-linux"

BUILD_PYTHON_DIST=${CUR_DIR}/build-python.dist
BUILD_PYTHON_DIST_PYTHON=${BUILD_PYTHON_DIST}/bin/python3

BUILD_PYTHON_BIN="${BUILD_PYTHON_DIST}/bin"
BUILD_PYTHON=$BUILD_PYTHON_BIN/python3
BUILD_PIP=$BUILD_PYTHON_BIN/pip3

HOST_PYTHON_DIST=${TARGET_ROOT}.python3
HOST_PYTHON_BIN="${HOST_PYTHON_DIST}/bin"
HOST_PYTHON=$HOST_PYTHON_BIN/python3
HOST_PIP=$HOST_PYTHON_BIN/pip3
HOST_MESON=$HOST_PYTHON_BIN/meson

MESON_CROSS_ROOT=${CUR_DIR}/meson-scripts
MESON_CROSS_FILE_BASE=${MESON_CROSS_ROOT}/base.meson

# modify ARCH in meson config
update_config() {
    local filename="$1"
    sed -i "s/py_ver[[:space:]]*=[[:space:]]*'.*'/py_ver = '${PY_VERSION}'/g" "$filename"
    sed -i "s|ohos_sdk[[:space:]]*=[[:space:]]*'.*'|ohos_sdk = '${OHOS_SDK}'|g" "$filename"
    sed -i "s|proj_root[[:space:]]*=[[:space:]]*'.*'|proj_root = '${CUR_DIR}'|g" "$filename"
    sed -i -e "s/host_cpu[[:space:]]*=[[:space:]]*'.*'/host_cpu = '${OHOS_CPU}'/g" \
           -e "s/host_arch[[:space:]]*=[[:space:]]*'.*'/host_arch = '${OHOS_ARCH}'/g" "$filename"
}

set_meson_list() {
	local file="$1"
	local listname="$2"
	local listval="$3"
	local funcname="set_meson_list"

	if [ -z "$file" ] || [ -z "$listname" ]; then
		printf "Usage: $funcname <meson-file> <list-name> <list-value>\n" >&2
		return 1
	fi
	if [ ! -f "$file" ]; then
		error "$funcname: file not found: $file" >&2
		return 1
	fi

	# Build the Meson list from listval (split on whitespace)
	local -a arr
		if [ -n "${listval:-}" ]; then
		read -r -a arr <<< "$listval"
	fi

	local elements=""
	local f safe
	for f in "${arr[@]}"; do
		# escape backslashes then single quotes
		safe=$(printf '%s' "$f" | sed -e 's/\\/\\\\/g' -e "s/'/\\\\'/g")
		if [ -n "$elements" ]; then
			elements+=", "
		fi
		elements+="'$safe'"
	done

	local repl
	if [ -z "$elements" ]; then
		repl="$listname = []"
	else
		repl="$listname = [ $elements ]"
	fi

	# Use awk to replace a block like:
	#   common_c_flags = [ .... ]
	# Whether it's single-line or multi-line. If not found, append at end.
	local tmp="${file}.$$.tmp"
	awk -v R="$repl" -v L="$listname" '
	BEGIN { found=0; skip=0 }
	{
		if (skip) {
			# if this line closes the bracketed list, stop skipping and continue
			if (index($0, "]") > 0) { skip=0; next }
			next
		}
		# build a pattern: ^\s*L\s*=
		# awk string concatenation allows using L directly in match()
		if (match($0, "^[[:space:]]*" L "[[:space:]]*=")) {
			print R
			found=1
			# If the same line also contains the closing ']' then nothing to skip;
			# otherwise skip following lines until we find a line containing ']'
			if (index($0, "]") == 0) { skip=1 }
			next
		}
		print
	}
	END {
		if (!found) {
			# append the replacement as a new line at EOF
			print ""
			print R
		}
	}' "$file" > "$tmp" || { error "$funcname: failed to write temp file" >&2; rm -f "$tmp"; return 1; }

	mv "$tmp" "$file" || { error "$funcname: failed to move temp file into place" >&2; rm -f "$tmp"; return 1; }

	info "$funcname: updated list field '$listname' in $file"
	return 0
}

reset_meson() {
	script=${1:-}
	if [ ! -f "$script" ]; then
		error "invalid meson configure file: '$script'"
		exit 1
	fi
	cp $script.template $script
	update_config $script
}

enter_pycrossenv() {
	if [[ ! -d ${PY_CROSS_ROOT} ]]; then
		$BUILD_PIP install crossenv
		$BUILD_PYTHON -m crossenv \
			$HOST_PYTHON \
			crossenv_${OHOS_CPU}
	fi
	. ${CROSS_ROOT}/bin/activate
}

exit_pycrossenv() {
	deactivate
}


if [ ! -d ${CUR_DIR}/meson-scripts ]; then
    warn "cannot find meson template directory: ${CUR_DIR}/meson-scripts"
else
	for ms_template in "${CUR_DIR}/meson-scripts"/*.meson.template; do
		ms_sh="${ms_template%.*}"
		# recover from template
		cp $ms_sh.template $ms_sh
		update_config $ms_sh
	done
    # update_config ${CUR_DIR}/meson-scripts/ohos-build.meson
    # update_config ${CUR_DIR}/meson-scripts/scipy-build.meson
    # update_config ${CUR_DIR}/meson-scripts/scipy-build.numpy2.meson
    
    # escaped_dir=$(printf '%s\n' "$CUR_DIR" | sed -e 's/[&/\]/\\&/g')
    # sed -i "s|proj_root[[:space:]]*=[[:space:]]*'[^']*'|proj_root='$escaped_dir'|g" meson-scripts/scipy-build.meson
    # sed -i "s|proj_root[[:space:]]*=[[:space:]]*'[^']*'|proj_root='$escaped_dir'|g" meson-scripts/scipy-build.numpy2.meson
fi


PY_CROSS_ROOT=${CUR_DIR}/crossenv_${OHOS_CPU}
CROSS_ROOT=$PY_CROSS_ROOT
HOST_SITE_PKGS=${PY_CROSS_ROOT}/cross/lib/python${PY_VERSION}/site-packages

PYPKG_NATIVE_OUTPUT_DIR=${CUR_DIR}/dist-pypkgs.native.${OHOS_CPU}
PYPKG_OUTPUT_WHEEL_DIR=${CUR_DIR}/dist.wheels

# numpy >= 2 use different header location
NUMPY_LIBROOT=${HOST_SITE_PKGS}/numpy/core
NUMPY2_LIBROOT=${HOST_SITE_PKGS}/numpy/_core

mkdir -p ${PYPKG_OUTPUT_WHEEL_DIR}
