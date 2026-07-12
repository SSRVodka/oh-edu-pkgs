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

OHLOHA_ROOT=${CUR_DIR}/.ohloha
OHLOHA_LOCK_ROOT=${OHLOHA_ROOT}/locks
OHLOHA_TOOL_WRAPPER_ROOT=${OHLOHA_ROOT}/tool-wrappers
HOST_TOOLS_VENV=${OHLOHA_ROOT}/host-venv
HOST_TOOLS_BIN=${HOST_TOOLS_VENV}/bin
HOST_TOOLS_PYTHON=${HOST_TOOLS_BIN}/python3
HOST_TOOLS_PIP=${HOST_TOOLS_BIN}/pip
HOST_MATURIN=${HOST_TOOLS_BIN}/maturin
HOST_HATCHLING=${HOST_TOOLS_BIN}/hatchling
HOST_FLIT=${HOST_TOOLS_BIN}/flit
HOST_SWIG=${HOST_TOOLS_BIN}/swig
HOST_TOOLS_SITE_PKGS=""
PIP_CACHE_DIR=${OHLOHA_ROOT}/pip-cache
export PIP_CACHE_DIR

mkdir -p "${OHLOHA_LOCK_ROOT}" "${OHLOHA_TOOL_WRAPPER_ROOT}" "${PIP_CACHE_DIR}"

acquire_ohloha_lock() {
	local lock_name="${1:?lock name is required}"
	local out_var="${2:-}"
	local acquired_lock_dir="${OHLOHA_LOCK_ROOT}/${lock_name}.lock"
	local pid_file="${acquired_lock_dir}/pid"
	local waited=0
	local missing_pid_waits=0

	while ! mkdir "${acquired_lock_dir}" 2>/dev/null; do
		local owner_pid=""
		if [ -f "${pid_file}" ]; then
			owner_pid=$(cat "${pid_file}" 2>/dev/null || true)
		fi
		if [ -n "${owner_pid}" ] && ! kill -0 "${owner_pid}" 2>/dev/null; then
			warn "removing stale lock '${lock_name}' from pid ${owner_pid}"
			rm -rf "${acquired_lock_dir}"
			continue
		fi
		if [ -z "${owner_pid}" ]; then
			missing_pid_waits=$((missing_pid_waits + 1))
			if [ "${missing_pid_waits}" -ge 5 ]; then
				warn "removing stale lock '${lock_name}' without owner pid"
				rm -rf "${acquired_lock_dir}"
				missing_pid_waits=0
				continue
			fi
		else
			missing_pid_waits=0
		fi
		if [ "$waited" -eq 0 ]; then
			info "waiting for lock: ${lock_name}"
		fi
		waited=1
		sleep 1
	done
	printf '%s\n' "$$" > "${pid_file}"

	if [ -n "${out_var}" ]; then
		printf -v "${out_var}" '%s' "${acquired_lock_dir}"
	else
		printf '%s\n' "${acquired_lock_dir}"
	fi
}

release_ohloha_lock() {
	local lock_dir="${1:-}"

	case "${lock_dir}" in
		"${OHLOHA_LOCK_ROOT}"/*.lock)
			rm -rf "${lock_dir}"
			;;
		"")
			;;
		*)
			error "refusing to release unexpected lock path: ${lock_dir}"
			return 1
			;;
	esac
}

with_ohloha_lock() {
	local lock_name="${1:?lock name is required}"
	shift
	local lock_dir=""
	local rc=0

	acquire_ohloha_lock "${lock_name}" lock_dir || return 1
	"$@" || rc=$?
	release_ohloha_lock "${lock_dir}" || return 1
	return "$rc"
}

ensure_symlink() {
	local target="${1:?symlink target is required}"
	local link_path="${2:?symlink path is required}"
	local tmp_link

	if [ "$(readlink "${link_path}" 2>/dev/null || true)" = "${target}" ]; then
		return 0
	fi

	tmp_link="${link_path}.tmp.$$"
	rm -f "${tmp_link}"
	ln -s "${target}" "${tmp_link}"
	mv -Tf "${tmp_link}" "${link_path}"
}

ensure_host_tools_unlocked() {
	if [ ! -x "${HOST_TOOLS_PYTHON}" ]; then
		info "creating host tools venv: ${HOST_TOOLS_VENV}"
		python3 -m venv "${HOST_TOOLS_VENV}"
	fi

	local -a missing_tools=()
	if ! "${HOST_TOOLS_PYTHON}" -c 'import mesonbuild' >/dev/null 2>&1; then
		missing_tools+=(meson)
	fi
	if [ ! -x "${HOST_TOOLS_BIN}/ninja" ]; then
		missing_tools+=(ninja)
	fi
	if ! "${HOST_TOOLS_PYTHON}" -c 'import crossenv' >/dev/null 2>&1; then
		missing_tools+=(crossenv)
	fi
	if [ ! -x "${HOST_MATURIN}" ]; then
		missing_tools+=(maturin)
	fi
	# needed by python3-pydantic, python3-annotated-types
	if [ ! -x "${HOST_HATCHLING}" ]; then
		missing_tools+=(hatchling)
	fi
	# needed by python3-typing-extensions
	if [ ! -x "${HOST_FLIT}" ]; then
		missing_tools+=(flit)
	fi
	if [ ! -x "${HOST_SWIG}" ]; then
		missing_tools+=(swig)
	fi
	# needed by native Python packages using modern PEP 517 backends.
	if ! "${HOST_TOOLS_PYTHON}" -c 'import setuptools_scm' >/dev/null 2>&1; then
		missing_tools+=(setuptools-scm)
	fi
	if ! "${HOST_TOOLS_PYTHON}" -c 'import cppy' >/dev/null 2>&1; then
		missing_tools+=(cppy)
	fi
	if ! "${HOST_TOOLS_PYTHON}" -c 'import scikit_build_core' >/dev/null 2>&1; then
		missing_tools+=(scikit-build-core)
	fi
	if ! "${HOST_TOOLS_PYTHON}" -c 'import mesonpy' >/dev/null 2>&1; then
		missing_tools+=(meson-python)
	fi
	if ! "${HOST_TOOLS_PYTHON}" -c 'import pybind11' >/dev/null 2>&1; then
		missing_tools+=(pybind11)
	fi
	if ! "${HOST_TOOLS_PYTHON}" -c 'import pythran' >/dev/null 2>&1; then
		missing_tools+=(pythran)
	fi
	if ! "${HOST_TOOLS_PYTHON}" -c 'import setuptools_rust' >/dev/null 2>&1; then
		missing_tools+=(setuptools-rust)
	fi
	if ! "${HOST_TOOLS_PYTHON}" -c 'import pipcl' >/dev/null 2>&1; then
		missing_tools+=(pipcl)
	fi

	if [ "${#missing_tools[@]}" -gt 0 ]; then
		info "installing missing host build tools into private venv: ${missing_tools[*]}"
		"${HOST_TOOLS_PYTHON}" -m pip install --disable-pip-version-check "${missing_tools[@]}"
	fi
}

ensure_host_tools() {
	with_ohloha_lock host-tools ensure_host_tools_unlocked
	HOST_TOOLS_SITE_PKGS=$("${HOST_TOOLS_PYTHON}" -c 'import sysconfig; print(sysconfig.get_path("purelib"))')
	export PATH="${HOST_TOOLS_BIN}:$PATH"
}

ensure_tool_wrappers_unlocked() {
	ensure_symlink "${OHOS_SDK}/native/llvm/bin/llvm-strip" "${TOOL_WRAPPER_BIN}/strip"
	ensure_symlink "${OHOS_SDK}/native/llvm/bin/llvm-profdata" "${TOOL_WRAPPER_BIN}/profdata"
	rm -f "${TOOL_WRAPPER_BIN}/ld.lld"

	local ld_emulation=""
	case "${OHOS_CPU}" in
		aarch64)
			ld_emulation="aarch64linux"
			;;
		arm)
			ld_emulation="armelf_linux_eabi"
			;;
		x86_64)
			ld_emulation="elf_x86_64"
			;;
		*)
			error "unsupported OHOS_CPU for ld.lld wrapper: ${OHOS_CPU}"
			return 1
			;;
	esac

	local binary_or_cxx_wrapper="${TOOL_WRAPPER_BIN}/ld.binary-input-or-cxx"
	rm -f "${TOOL_WRAPPER_BIN}/ld.lld-binary-input"
	cat > "${binary_or_cxx_wrapper}" <<EOF
#!/bin/bash
set -Eeuo pipefail

real_ld="${OHOS_SDK}/native/llvm/bin/ld.lld"
real_cxx="${OHOS_SDK}/native/llvm/bin/clang++"
ld_emulation="${ld_emulation}"
ohos_target="${OHOS_CPU}-linux-ohos"
ohos_sysroot="${OHOS_SDK}/native/sysroot"
ohos_sysroot_lib="${OHOS_SDK}/native/sysroot/usr/lib/${OHOS_CPU}-linux-ohos"
uses_binary_input=false
has_emulation=false
previous_arg=""

for arg in "\$@"; do
	case "\$arg" in
		-m|-m*)
			has_emulation=true
			;;
		-b=binary|--format=binary)
			uses_binary_input=true
			;;
		binary)
			if [ "\$previous_arg" = "-b" ]; then
				uses_binary_input=true
			fi
			;;
	esac
	previous_arg="\$arg"
done

# MuPDF embeds resource files with \`ld -r -b binary\`. The OHOS SDK ld.lld
# cannot infer an output architecture from raw binary input, so pass an
# emulation explicitly for that one mode.
if [ "\$uses_binary_input" = true ]; then
	if [ "\$has_emulation" = false ]; then
		exec "\$real_ld" -m "\$ld_emulation" "\$@"
	fi
	exec "\$real_ld" "\$@"
fi

# PyMuPDF later reuses \$LD for normal Python extension links, but passes
# compiler-driver flags such as -DNDEBUG, -MD/-MF and -Wl,*. Route non-binary
# links through clang++ while keeping the raw ld.lld path above for resources.
exec "\$real_cxx" --target="\$ohos_target" --sysroot="\$ohos_sysroot" -fuse-ld=lld -L"\$ohos_sysroot_lib" "\$@"
EOF
	chmod +x "${binary_or_cxx_wrapper}"

	cat > "${TOOL_WRAPPER_BIN}/gfortran" <<EOF
#!/bin/bash
set -Eeuo pipefail

real_fc="${OHOS_CPU}-linux-gnu-gfortran"
ohos_clang="${OHOS_SDK}/native/llvm/bin/clang"
ohos_target="${OHOS_CPU}-linux-ohos"
ohos_sysroot="${OHOS_SDK}/native/sysroot"
rt_dir="${PATCH_FILE_ROOT}/libgfortran_rt/${OHOS_CPU}"

compile_only=false
inputs=()
link_inputs=()
linker_probe=false

for arg in "\$@"; do
	case "\$arg" in
		--print-search-dirs|-print-search-dirs)
			printf 'install: =\\n'
			printf 'programs: =\\n'
			printf 'libraries: =%s\\n' "\$rt_dir"
			exit 0
			;;
		-print-file-name=libgfortran.so|-print-file-name=libgfortran.so.5)
			printf '%s/libgfortran.so.5\\n' "\$rt_dir"
			exit 0
			;;
		-print-file-name=libgcc_s.so|-print-file-name=libgcc_s.so.1)
			printf '%s/libgcc_s.so.1\\n' "\$rt_dir"
			exit 0
			;;
		-print-file-name=libquadmath.so|-print-file-name=libquadmath.so.0)
			printf '%s/libquadmath.so.0\\n' "\$rt_dir"
			exit 0
			;;
		-v|--version|-dumpversion|-dumpfullversion|-print-*|--print-*)
			exec "\$real_fc" "\$@"
			;;
		-c|-S|-E)
			compile_only=true
			;;
		-Wl,--version|-Wl,-v)
			linker_probe=true
			;;
		*.f|*.F|*.for|*.FOR|*.f90|*.F90|*.f95|*.F95|*.f03|*.F03|*.f08|*.F08)
			inputs+=("\$arg")
			;;
		*.o|*.a|*.so|*.so.*)
			link_inputs+=("\$arg")
			;;
	esac
done

if [ ! -d "\$rt_dir" ]; then
	echo "ERROR: missing libgfortran runtime: \$rt_dir" >&2
	exit 1
fi

filter_clang_driver_args() {
	local filtered=()
	local skip_next=false
	local arg
	for arg in "\$@"; do
		if [ "\$skip_next" = true ]; then
			skip_next=false
			continue
		fi
		case "\$arg" in
			--target=*|--sysroot=*|-fuse-ld=*)
				;;
			--target|--sysroot)
				skip_next=true
				;;
			*)
				filtered+=("\$arg")
				;;
		esac
	done
	printf '%s\\0' "\${filtered[@]}"
}

is_fortran_source() {
	case "\${1:-}" in
		*.f|*.F|*.for|*.FOR|*.f90|*.F90|*.f95|*.F95|*.f03|*.F03|*.f08|*.F08)
			return 0
			;;
	esac
	return 1
}

build_fortran_source_compile_args() {
	compile_args=()
	local skip_next=false
	local arg
	for arg in "\$@"; do
		if [ "\$skip_next" = true ]; then
			skip_next=false
			continue
		fi
		case "\$arg" in
			-o|--target|--sysroot)
				skip_next=true
				;;
			--target=*|--sysroot=*|-fuse-ld=*|-shared|-Wl,*|-L*|-l*|*.o|*.a|*.so|*.so.*)
				;;
			*)
				if ! is_fortran_source "\$arg"; then
					compile_args+=("\$arg")
				fi
				;;
		esac
	done
}

build_clang_link_args() {
	link_args=()
	compile_args=()
	build_fortran_source_compile_args "\$@"

	local skip_next=false
	local keep_next=false
	local arg obj
	local src_index=0
	for arg in "\$@"; do
		if [ "\$skip_next" = true ]; then
			skip_next=false
			continue
		fi
		if [ "\$keep_next" = true ]; then
			link_args+=("\$arg")
			keep_next=false
			continue
		fi
		case "\$arg" in
			--target=*|--sysroot=*|-fuse-ld=*)
				;;
			--target|--sysroot)
				skip_next=true
				;;
			-o)
				link_args+=("\$arg")
				keep_next=true
				;;
			*)
				if is_fortran_source "\$arg"; then
					obj="\$tmpdir/fortran-\${src_index}.o"
					src_index=\$((src_index + 1))
					"\$real_fc" "\${compile_args[@]}" -c "\$arg" -o "\$obj"
					link_args+=("\$obj")
				else
					link_args+=("\$arg")
				fi
				;;
		esac
	done
}

if [ "\$compile_only" = true ] || { [ "\$linker_probe" = false ] && [ "\${#inputs[@]}" -eq 0 ] && [ "\${#link_inputs[@]}" -eq 0 ]; }; then
	mapfile -d '' fc_args < <(filter_clang_driver_args "\$@")
	exec "\$real_fc" "\${fc_args[@]}"
fi

tmpdir=\$(mktemp -d)
trap 'rm -rf "\$tmpdir"' EXIT
link_args=()
compile_args=()
build_clang_link_args "\$@"

exec "\$ohos_clang" --target="\$ohos_target" --sysroot="\$ohos_sysroot" -fuse-ld=lld \\
	-L"\$rt_dir" "\${link_args[@]}" -l:libgfortran.so.5 -l:libgcc_s.so.1 \\
	-Wl,-rpath,\\\$ORIGIN -Wl,-rpath,\\\$ORIGIN/.. \\
	-Wl,-rpath,\\\$ORIGIN/../.. -Wl,-rpath,\\\$ORIGIN/../../.. \\
	-lm -lc
EOF
	chmod +x "${TOOL_WRAPPER_BIN}/gfortran"
}

ensure_tool_wrappers() {
	with_ohloha_lock "tool-wrappers-${OHOS_SDK_API_VERSION}-${OHOS_CPU}" ensure_tool_wrappers_unlocked
}

if [ -z "${OHOS_SDK:-}" ]; then
	warn "please set OHOS_SDK env first"
	exit 1
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

SRC_ROOT=${OHLOHA_ROOT}/legacy-src
mkdir -p "${SRC_ROOT}"
TARGET_ROOT=${CUR_DIR}/dist.${OHOS_CPU}
TEST_DIR=${CUR_DIR}/test-only

PATCH_FILE_ROOT=${CUR_DIR}/patches

# export for cmake toolchain file
export OHOS_LIBDIR=lib
# Set this for OHOS sdk installation
# export OHOS_LIBDIR=lib/${OHOS_CPU}-linux-ohos

ensure_host_tools

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
export RANLIB=${OHOS_SDK}/native/llvm/bin/llvm-ranlib
export OBJDUMP=${OHOS_SDK}/native/llvm/bin/llvm-objdump
export OBJCOPY=${OHOS_SDK}/native/llvm/bin/llvm-objcopy
export READELF=${OHOS_SDK}/native/llvm/bin/llvm-readelf
export NM=${OHOS_SDK}/native/llvm/bin/llvm-nm
export AR=${OHOS_SDK}/native/llvm/bin/llvm-ar
export PROFDATA=${OHOS_SDK}/native/llvm/bin/llvm-profdata
TOOL_WRAPPER_BIN=${OHLOHA_TOOL_WRAPPER_ROOT}/${OHOS_SDK_API_VERSION}/${OHOS_CPU}/bin
mkdir -p "${TOOL_WRAPPER_BIN}"
ensure_tool_wrappers
export OHOS_LD_BINARY_INPUT_OR_CXX=${TOOL_WRAPPER_BIN}/ld.binary-input-or-cxx
#export CFLAGS="-fPIC -D__MUSL__=1 -D__OPENHARMONY__=1 -I${HOST_SYSROOT}/usr/include -I${HOST_SYSROOT}/usr/include/${OHOS_CPU}-linux-ohos"
# keep track with ohos.toolchain.cmake + CMAKE_C_FLAGS_INIT
# including arch-dependent headers
export CFLAGS="-fPIC -D__MUSL__ -D__OHOS__ -D__OPENHARMONY__ -Wno-shorten-64-to-32 -Wno-unused-command-line-argument -I${HOST_SYSROOT}/usr/include -I${HOST_SYSROOT}/usr/include/${OHOS_CPU}-linux-ohos"
export CXXFLAGS=${CFLAGS}
export CPPFLAGS=${CXXFLAGS}
#export LDFLAGS="-fuse-ld=lld -L${HOST_SYSROOT}/usr/${OHOS_LIBDIR}"
export LDFLAGS="-fuse-ld=lld -lm -L${HOST_SYSROOT}/usr/${OHOS_LIBDIR}"
export LDSHARED="${CC} ${LDFLAGS} -shared"

export PATH=${TOOL_WRAPPER_BIN}:$PATH:${OHOS_SDK}/native/llvm/bin:${OHOS_SDK}/native/toolchains

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
	local make_install_target="${8:-install}"

	local OLD_CFLAGS="${CFLAGS:-}"
	local OLD_CXXFLAGS="${CXXFLAGS:-}"
	local OLD_CPPFLAGS="${CPPFLAGS:-}"
	local OLD_LDFLAGS="${LDFLAGS:-}"
	local OLD_PKG_CONFIG_LIBDIR="${PKG_CONFIG_LIBDIR:-}"
	local install_prefix="${target_root_prefix_without_pkgname:-${TARGET_ROOT}}"
	local install_dir
	install_dir=$(get_pkg_install_dir "$target_dir")

	pushd "$configure_dir"

	local dep
	for dep in $deps; do
		local dep_prefix
		dep_prefix=$(get_pkg_dst_dir "$dep") || return 1
		CFLAGS="-I${dep_prefix}/include ${CFLAGS:-}"
		LDFLAGS="-L${dep_prefix}/${OHOS_LIBDIR} ${LDFLAGS:-}"
		PKG_CONFIG_LIBDIR="${dep_prefix}/${OHOS_LIBDIR}/pkgconfig:${PKG_CONFIG_LIBDIR:-}"
	done

	CXXFLAGS="${CFLAGS:-}"
	CPPFLAGS="${CFLAGS:-}"

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

	configure_flags="${extra_configure_flags} --prefix=${install_prefix}"
	configure_flags="${configure_flags} --libdir=${install_prefix}/${OHOS_LIBDIR}"

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
	info "cflags: ${CFLAGS:-}"
	info "ldflags: ${LDFLAGS:-}"
	info "pkgconfig_libdir: ${PKG_CONFIG_LIBDIR:-}"
	$configure_exe $configure_flags || { return 1; }
	current_build_root=$(readlink -f .)
	if [ "x${pkg_build_type:-}" != "xcustom" ]; then
		post_configure_hook || { error "post_configure_hook failed for ${target_dir}"; return 1; }
	fi

	#read -p "check >>> "
	make -j${make_parallism} || { return 1; }
	#read -p "check >>> "
	make ${make_install_target} || { return 1; }

	CFLAGS="$OLD_CFLAGS"
	CXXFLAGS="$OLD_CXXFLAGS"
	CPPFLAGS="$OLD_CPPFLAGS"
	LDFLAGS="$OLD_LDFLAGS"
	PKG_CONFIG_LIBDIR="$OLD_PKG_CONFIG_LIBDIR"

	popd
	if [ -d "$install_dir" ]; then
		# merge directory
		cp -r ${install_prefix}/* "$install_dir"/
		rm -rf ${install_prefix}
	else
		mv ${install_prefix} "$install_dir"
	fi
	local dst_dir=${install_dir}/${OHOS_LIBDIR}
	if [ ! -d "$dst_dir" ]; then
		warn "library '$target_dir' doesn't have an arch-dependent library directory '$dst_dir'"
	else
		patch_libdir_origin $target_dir
	fi
	# some package configs may locate in share/: like xorg, asio (header-only)
	sharedir=${install_dir}/share
	if [ -d $sharedir ]; then
		patch_libdir_origin $target_dir "" "" "${install_dir}/share"
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
	local install_dir
	install_dir=$(get_pkg_install_dir "$target_dir")
	for dep in $deps; do
		local dep_prefix
		dep_prefix=$(get_pkg_dst_dir "$dep")
		_extra_cflags="-I${dep_prefix}/include ${_extra_cflags}"
		_extra_ldflags="-L${dep_prefix}/${OHOS_LIBDIR} ${_extra_ldflags}"
		local _tmp_cmakedir="${dep_prefix}/${OHOS_LIBDIR}/cmake"
		if [ -d "$_tmp_cmakedir" ]; then
			# non-recursive
			for _item in "$_tmp_cmakedir"/*; do
				if [ ! -e "$_item" ]; then
					continue
				fi
				_extra_cmakeprefix="$_item;${_extra_cmakeprefix}"
			done
		fi
		_extra_cmakefindroot="${dep_prefix};${_extra_cmakefindroot}"
		PKG_CONFIG_LIBDIR="${dep_prefix}/${OHOS_LIBDIR}/pkgconfig:$PKG_CONFIG_LIBDIR"
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
		-DCMAKE_INSTALL_PREFIX=${install_dir} \
		-DCMAKE_INSTALL_LIBDIR=${OHOS_LIBDIR} \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_VERBOSE_MAKEFILE=ON \
		-DCMAKE_CROSSCOMPILING=ON \
		-B ${_my_cmake_builddir} || { return 1; }
	current_build_root=$(readlink -f "${_my_cmake_builddir}")
	if [ "x${pkg_build_type:-}" != "xcustom" ]; then
		post_configure_hook || { error "post_configure_hook failed for ${target_dir}"; return 1; }
	fi

	#read -p "Check >>> "
	${CMAKE_BIN} --build ${_my_cmake_builddir} -j${parallism} || { return 1; }
	${CMAKE_BIN} --install ${_my_cmake_builddir} || { return 1; }

	PKG_CONFIG_LIBDIR="$OLD_PKG_CONFIG_LIBDIR"
	popd

	local dst_archlibdir=${install_dir}/${OHOS_LIBDIR}
	if [ ! -d "$dst_archlibdir" ]; then
		warn "library '$target_dir' doesn't have an arch-dependent library directory '$dst_archlibdir'"
	else
		patch_libdir_origin $target_dir
	fi
	# some package configs may locate in share/: like xorg, asio (header-only)
	sharedir=${install_dir}/share
	if [ -d $sharedir ]; then
		patch_libdir_origin $target_dir "" "" "${install_dir}/share"
	fi
}

build_mesonproj_with_deps() {
	local target_dir=$1
	local deps=${2:-}
	local meson_cross_file=${3:-${MESON_CROSS_FILE_BASE}}
	local _my_extra_meson_flags=${4:-}
	local parallism=${5:-20}
	local _my_extra_cflags=${6:-}
	local _my_extra_ldflags=${7:-}
	local _my_extra_cmake_prefix=${8-}
	local _my_extra_cmake_findroot=${9:-}
	local _my_meson_builddir=${10:-ohos-build}

	pushd $target_dir
	local _my_meson_sourcedir
	_my_meson_sourcedir=$(readlink -f .)
	mkdir -p "$_my_meson_builddir"
	pushd "$_my_meson_builddir"

	local dep
	local _extra_cflags=""
	local _extra_ldflags=""
	local _extra_cmakeprefix=""
	local _extra_cmakefindroot="$_my_extra_cmake_findroot"
	local OLD_PKG_CONFIG_LIBDIR="$PKG_CONFIG_LIBDIR"
	local install_dir
	install_dir=$(get_pkg_install_dir "$target_dir")
	for dep in $deps; do
		local dep_prefix
		dep_prefix=$(get_pkg_dst_dir "$dep")
		_extra_cflags="-I${dep_prefix}/include ${_extra_cflags}"
		_extra_ldflags="-L${dep_prefix}/${OHOS_LIBDIR} ${_extra_ldflags}"
		local _tmp_cmakedir="${dep_prefix}/${OHOS_LIBDIR}/cmake"
		if [ -d "$_tmp_cmakedir" ]; then
			# non-recursive
			for _item in "$_tmp_cmakedir"/*; do
				if [ ! -e "$_item" ]; then
					continue
				fi
				_extra_cmakeprefix="$_item;${_extra_cmakeprefix}"
			done
		fi
		_extra_cmakefindroot="${dep_prefix};${_extra_cmakefindroot}"
		PKG_CONFIG_LIBDIR="${dep_prefix}/${OHOS_LIBDIR}/pkgconfig:$PKG_CONFIG_LIBDIR"
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
		--prefix=${install_dir} \
		--libdir=${OHOS_LIBDIR} \
		--buildtype=release \
		${_my_extra_meson_flags} \
		"$_my_meson_sourcedir" \
	|| { return 1; }
	current_build_root=$(readlink -f .)
	if [ "x${pkg_build_type:-}" != "xcustom" ]; then
		post_configure_hook || { error "post_configure_hook failed for ${target_dir}"; return 1; }
	fi
	# read -p "check >>> "
	ninja -v -j${parallism} || { return 1; }
	ninja install || { return 1; }

	PKG_CONFIG_LIBDIR="$OLD_PKG_CONFIG_LIBDIR"
	popd
	popd

	local dst_archlibdir=${install_dir}/${OHOS_LIBDIR}
	if [ ! -d "$dst_archlibdir" ]; then
		warn "library '$target_dir' doesn't have an arch-dependent library directory '$dst_archlibdir'"
	else
		patch_libdir_origin $target_dir
	fi
	# some package configs may locate in share/: like xorg, asio (header-only)
	sharedir=${install_dir}/share
	if [ -d $sharedir ]; then
		patch_libdir_origin $target_dir "" "" "${install_dir}/share"
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
		dst_prefix=$(get_pkg_dst_dir "$target_dir")
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

BUILD_PYTHON_DIST=${OHLOHA_ROOT}/native/build-python
BUILD_PYTHON_DIST_PYTHON=${BUILD_PYTHON_DIST}/bin/python3
BUILD_PYTHON_DIST_PIP=${BUILD_PYTHON_DIST}/bin/pip3

BUILD_PYTHON_BIN="${BUILD_PYTHON_DIST}/bin"
BUILD_PYTHON_WRAPPER_ROOT=${OHLOHA_TOOL_WRAPPER_ROOT}/build-python
BUILD_PYTHON=${BUILD_PYTHON_WRAPPER_ROOT}/python3
BUILD_PIP=${BUILD_PYTHON_WRAPPER_ROOT}/pip3

ensure_build_python_wrappers() {
	mkdir -p "${BUILD_PYTHON_WRAPPER_ROOT}"
	cat > "${BUILD_PYTHON}" <<EOF
#!/bin/sh
export LD_LIBRARY_PATH="${BUILD_PYTHON_DIST}/lib:\${LD_LIBRARY_PATH:-}"
exec "${BUILD_PYTHON_DIST_PYTHON}" "\$@"
EOF
	chmod +x "${BUILD_PYTHON}"
	cat > "${BUILD_PIP}" <<EOF
#!/bin/sh
export LD_LIBRARY_PATH="${BUILD_PYTHON_DIST}/lib:\${LD_LIBRARY_PATH:-}"
exec "${BUILD_PYTHON_DIST_PIP}" "\$@"
EOF
	chmod +x "${BUILD_PIP}"
}
ensure_build_python_wrappers

HOST_PYTHON_DIST="${HOST_PYTHON_DIST:-}"
if [ -n "$HOST_PYTHON_DIST" ]; then
	HOST_PYTHON_BIN="${HOST_PYTHON_DIST}/bin"
	HOST_PYTHON=$HOST_PYTHON_BIN/python3
	HOST_PIP=$HOST_PYTHON_BIN/pip3
	HOST_MESON=$HOST_PYTHON_BIN/meson
else
	HOST_PYTHON_BIN=""
	HOST_PYTHON=""
	HOST_PIP=""
	HOST_MESON=""
fi

MESON_CROSS_TEMPLATE_ROOT=${CUR_DIR}/meson-scripts
MESON_CROSS_ROOT=${OHLOHA_ROOT}/meson-cross/${OHOS_SDK_API_VERSION}/${OHOS_CPU}/pid-$$
MESON_CROSS_FILE_BASE=${MESON_CROSS_ROOT}/base.meson

PY_CROSS_ROOT=${OHLOHA_ROOT}/crossenv/${OHOS_SDK_API_VERSION}/${OHOS_CPU}
CROSS_ROOT=$PY_CROSS_ROOT
HOST_SITE_PKGS=${PY_CROSS_ROOT}/cross/lib/python${PY_VERSION}/site-packages
PYCROSS_CROSS_PYTHON=${PY_CROSS_ROOT}/cross/bin/python3
PYCROSS_CROSS_PIP=${PY_CROSS_ROOT}/cross/bin/pip
PYCROSS_BUILD_PIP=${PY_CROSS_ROOT}/build/bin/pip

PYPKG_OUTPUT_WHEEL_DIR=${CUR_DIR}/dist.wheels

# numpy >= 2 use different header location
NUMPY_LIBROOT=${HOST_SITE_PKGS}/numpy/core
NUMPY2_LIBROOT=${HOST_SITE_PKGS}/numpy/_core

# modify ARCH in meson config
update_config() {
    local filename="$1"
    sed -i "s/py_ver[[:space:]]*=[[:space:]]*'.*'/py_ver = '${PY_VERSION}'/g" "$filename"
    sed -i "s|ohos_sdk[[:space:]]*=[[:space:]]*'.*'|ohos_sdk = '${OHOS_SDK}'|g" "$filename"
    sed -i "s|proj_root[[:space:]]*=[[:space:]]*'.*'|proj_root = '${CUR_DIR}'|g" "$filename"
    sed -i "s|py_cross_root[[:space:]]*=[[:space:]]*'.*'|py_cross_root = '${PY_CROSS_ROOT}'|g" "$filename"
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
	if [ ! -f "$script.template" ]; then
		error "missing meson template for '$script'"
		exit 1
	fi
	cp "$script.template" "$script"
	update_config "$script"
}

generate_meson_cross_files() {
	local template_root="${1:-${MESON_CROSS_TEMPLATE_ROOT}}"
	local output_root="${2:-${MESON_CROSS_ROOT}}"

	if [ ! -d "$template_root" ]; then
		warn "cannot find meson template directory: ${template_root}"
		return 0
	fi

	mkdir -p "$output_root"

	local ms_template ms_name ms_dst_template ms_dst
	for ms_template in "$template_root"/*.meson.template; do
		[ -f "$ms_template" ] || continue
		ms_name=$(basename "$ms_template")
		ms_dst_template="${output_root}/${ms_name}"
		ms_dst="${ms_dst_template%.template}"

		cp "$ms_template" "$ms_dst_template"
		cp "$ms_template" "$ms_dst"
		update_config "$ms_dst"
	done
}

enter_pycrossenv() {
	if [[ ! -f ${CROSS_ROOT}/bin/activate ]]; then
		rm -rf "${PY_CROSS_ROOT}"
		mkdir -p "$(dirname "${PY_CROSS_ROOT}")"
		# Build-python is a repo-private Python 3.12 used to create the crossenv so
		# its generated build/cross venvs match the target Python ABI.  crossenv is
		# installed in the host-tools venv, so load only that module path explicitly;
		# exporting PYTHONPATH here would leak host-tools pip into the generated venv.
		env -u PYTHONPATH "${BUILD_PYTHON}" - "${HOST_TOOLS_SITE_PKGS}" "$HOST_PYTHON" "${CROSS_ROOT}" <<'PY' || return 1
import runpy
import sys

site_pkgs, host_python, cross_root = sys.argv[1:4]
sys.path.insert(0, site_pkgs)
sys.argv = ["crossenv", host_python, cross_root]
runpy.run_module("crossenv", run_name="__main__")
PY
	fi
	. "${CROSS_ROOT}/bin/activate" || return 1
}

exit_pycrossenv() {
	deactivate || return 1
}

ohos_rust_target_for_cpu() {
	case "${1:-}" in
		aarch64) printf '%s' "aarch64-unknown-linux-ohos" ;;
		arm) printf '%s' "armv7-unknown-linux-ohos" ;;
		x86_64) printf '%s' "x86_64-unknown-linux-ohos" ;;
		*) error "unsupported OHOS_CPU for Rust/PyO3: '${1:-}'"; return 1 ;;
	esac
}

cargo_env_key_for_target() {
	printf '%s' "${1:-}" | tr '[:lower:]-' '[:upper:]_'
}

setup_pyo3_rust_cross_env() {
	# PyO3/maturin builds still need the Python crossenv for the target interpreter
	# and target site-packages, so this helper owns setup/teardown when the caller
	# has not already entered pycrossenv.
	local rc=0
	_pyo3_rust_started_pycrossenv=false
	if [ -z "${pycrossenv_lock_dir:-}" ]; then
		setup_pycrossenv || return 1
		_pyo3_rust_started_pycrossenv=true
	fi

	if [ ! -x "${HOST_MATURIN}" ]; then
		error "maturin not found in host tools venv: ${HOST_MATURIN}"
		destroy_pyo3_rust_cross_env || true
		return 1
	fi
	if ! command -v cargo >/dev/null 2>&1; then
		error "cargo not found; install Rust toolchain before building pyo3-rust packages"
		destroy_pyo3_rust_cross_env || true
		return 1
	fi

	local rust_target cargo_key cc_env_key ohos_target cc_bin cxx_bin cxx_inc python_prefix
	rust_target=$(ohos_rust_target_for_cpu "${OHOS_CPU}") || rc=$?
	if [ "$rc" -eq 0 ]; then
		ensure_pyo3_rust_target "${rust_target}" || rc=$?
	fi
	if [ "$rc" -ne 0 ]; then
		destroy_pyo3_rust_cross_env || true
		return "$rc"
	fi
	cargo_key=$(cargo_env_key_for_target "${rust_target}")
	cc_env_key="${rust_target//-/_}"
	ohos_target="${OHOS_CPU}-linux-ohos"
	cc_bin="${OHOS_SDK}/native/llvm/bin/clang"
	cxx_bin="${OHOS_SDK}/native/llvm/bin/clang++"
	cxx_inc="${OHOS_SDK}/native/llvm/include/libcxx-ohos/include/c++/v1"
	python_prefix=$(get_pkg_dst_dir python3) || rc=$?
	if [ "$rc" -ne 0 ]; then
		destroy_pyo3_rust_cross_env || true
		return "$rc"
	fi

	# Cargo and cc-rs use target-qualified env var names.  Keep this mapping here
	# so package BUILD files do not need to know OHOS target triples or SDK paths.
	export CARGO_BUILD_TARGET="${rust_target}"
	export "CARGO_TARGET_${cargo_key}_LINKER=${cc_bin}"
	export "CARGO_TARGET_${cargo_key}_AR=${AR}"
	export "CC_${cargo_key}=${cc_bin}"
	export "CXX_${cargo_key}=${cxx_bin}"
	export "AR_${cargo_key}=${AR}"
	export "CFLAGS_${cargo_key}=--target=${ohos_target} --sysroot=${HOST_SYSROOT} ${CFLAGS:-}"
	export "CXXFLAGS_${cargo_key}=--target=${ohos_target} --sysroot=${HOST_SYSROOT} -I${cxx_inc} ${CXXFLAGS:-}"
	export "CC_${cc_env_key}=${cc_bin}"
	export "CXX_${cc_env_key}=${cxx_bin}"
	export "AR_${cc_env_key}=${AR}"
	export "CFLAGS_${cc_env_key}=--target=${ohos_target} --sysroot=${HOST_SYSROOT} -I${python_prefix}/include/python${PY_VERSION} ${CFLAGS:-}"
	export "CXXFLAGS_${cc_env_key}=--target=${ohos_target} --sysroot=${HOST_SYSROOT} -I${python_prefix}/include/python${PY_VERSION} -I${cxx_inc} ${CXXFLAGS:-}"
	export CRATE_CC_NO_DEFAULTS=1
	export CXXSTDLIB="c++"
	export MATURIN_NO_WHEEL_REPAIR=1
	export PYO3_CROSS=1
	export PYO3_PYTHON="${PYCROSS_CROSS_PYTHON}"
	export PYO3_CROSS_PYTHON_VERSION="${PY_VERSION}"
	export PYO3_CROSS_LIB_DIR="${python_prefix}/${OHOS_LIBDIR}"
	export PYO3_CROSS_INCLUDE_DIR="${python_prefix}/include/python${PY_VERSION}"
	# Link the extension against the cross-built target libpython, not the host
	# Python used to run maturin.
	export RUSTFLAGS="-C linker=${cc_bin} \
		-C link-arg=--target=${ohos_target} \
		-C link-arg=--sysroot=${HOST_SYSROOT} \
		-C link-arg=-L${python_prefix}/${OHOS_LIBDIR} \
		-C link-arg=-lpython${PY_VERSION}"
}

ensure_pyo3_rust_target() {
	local rust_target="${1:-}"
	[ -n "${rust_target}" ] || { error "empty Rust target"; return 1; }
	if ! command -v rustup >/dev/null 2>&1; then
		if rustc --print target-list 2>/dev/null | grep -qx "${rust_target}"; then
			return 0
		fi
		error "rustup not found and rust target cannot be verified: ${rust_target}"
		return 1
	fi
	with_ohloha_lock "rust-target-${rust_target}" rustup target add "${rust_target}"
}

destroy_pyo3_rust_cross_env() {
	local rc=0
	if [ "x${_pyo3_rust_started_pycrossenv:-false}" = "xtrue" ]; then
		destroy_pycrossenv || rc=$?
	fi
	_pyo3_rust_started_pycrossenv=false
	return "$rc"
}

generate_meson_cross_files
mkdir -p "${PYPKG_OUTPUT_WHEEL_DIR}"
