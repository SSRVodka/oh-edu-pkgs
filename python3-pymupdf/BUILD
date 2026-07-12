#!/bin/bash
set -Eeuo pipefail

setup() {

pkg_version="1.28.0"
pkg_name="python3-pymupdf"
pkg_deps="python3>=3.10,libgettext>=0.24"
pkg_build_deps="python3>=3.10,libgettext>=0.24,python3-build,python3-setuptools"
pkg_source_url="https://files.pythonhosted.org/packages/8e/e9/6d6c5d6c0a3551bffd47681a6240caf941727f195b45593cf20ab36f018f/pymupdf-1.28.0.tar.gz"
pkg_release_url=""
pkg_license="Apache-2.0"
pkg_support_archs="x86_64,aarch64,arm"
pkg_build_type="custom"
pkg_build_parallism=""
pkg_force_clean_build=""
pkg_patch_files=""

pkg_build_autotools_extra_configure_flags=""
pkg_build_autotools_bootstrap_script=""
pkg_build_autotools_suffix_configure_flags=""
pkg_build_autotools_configure_dir=""
pkg_build_autotools_make_install_target=""
pkg_build_cmake_extra_cmake_flags=""
pkg_build_cmake_extra_cmake_prefix_path=""
pkg_build_cmake_extra_cflags=""
pkg_build_cmake_extra_cppflags=""
pkg_build_cmake_extra_ldflags=""
pkg_build_cmake_extra_cmake_findroot_path=""
pkg_build_meson_cross_file=""
pkg_build_meson_extra_meson_flags=""
pkg_build_meson_extra_cflags=""
pkg_build_meson_extra_ldflags=""
pkg_build_meson_extra_cmake_prefix_path=""
pkg_build_meson_extra_cmake_findroot_path=""

}

################# Hooks #################

native_env_hook() {
	:
}

custom_download_source() {
	_custom_download_source_continue=true
}

############### DO NOT MODIFY THIS PART #################
if [ "x${LOAD_NATIVE_HOOK_ONLY:-}" = "xtrue" ]; then
	return 0
fi
#########################################################

prebuilt_patch_hook() {
	:
}

prebuilt_patch_once_hook() {
	:
}

custom_build() {
	local build_rc=0
	local old_ld="${LD:-}"
	local old_ldxx="${LDXX:-}"
	local old_lld="${LLD:-}"
	local old_ldflags="${LDFLAGS:-}"
	local old_libclang_library_path="${LIBCLANG_LIBRARY_PATH+x${LIBCLANG_LIBRARY_PATH}}"
	local old_pymupdf_setup_libclang="${PYMUPDF_SETUP_LIBCLANG+x${PYMUPDF_SETUP_LIBCLANG}}"
	local old_pycross_python_config_extra_ldflags="${PYCROSS_PYTHON_CONFIG_EXTRA_LDFLAGS:-}"
	local python_prefix=""
	local gettext_prefix=""
	local libclang_version="18.1.1"
	local libclang_native_dir=""

	setup_pycrossenv || return 1

	if [ "$build_rc" -eq 0 ]; then
		python_prefix=$(get_pkg_dst_dir python3) || build_rc=$?
	fi
	if [ "$build_rc" -eq 0 ]; then
		gettext_prefix=$(get_pkg_dst_dir libgettext) || build_rc=$?
	fi
	if [ "$build_rc" -eq 0 ]; then
		# python3-config emits -lintl for this target Python; expose the package
		# that owns libintl instead of relying on global linker search paths.
		export LDFLAGS="-L${python_prefix}/${OHOS_LIBDIR} -L${gettext_prefix}/${OHOS_LIBDIR} ${LDFLAGS}"
		if [ ! -x "${OHOS_LD_BINARY_INPUT_OR_CXX:-}" ]; then
			error "missing OHOS binary-input/CXX LD wrapper"
			build_rc=1
		fi
	fi
	if [ "$build_rc" -eq 0 ]; then
		# PyMuPDF/MuPDF uses $LD both for `-r -b binary` resource objects and
		# for compiler-driver-style extension links; the wrapper handles both.
		local libclang_wheel_dir="${current_work_root}/host-libclang-wheel"
		local libclang_extract_dir="${current_work_root}/host-libclang"
		libclang_native_dir="${libclang_extract_dir}/libclang-${libclang_version}.data/platlib/clang/native"
		rm -rf "$libclang_wheel_dir" "$libclang_extract_dir"
		mkdir -p "$libclang_wheel_dir" "$libclang_extract_dir"
		"${HOST_TOOLS_PYTHON}" -m pip download --only-binary=:all: --no-deps -d "$libclang_wheel_dir" "libclang==${libclang_version}" || build_rc=$?
		if [ "$build_rc" -eq 0 ]; then
			local libclang_wheel
			libclang_wheel=$(find "$libclang_wheel_dir" -maxdepth 1 -type f -name "libclang-${libclang_version}-*.whl" | sort | head -n 1)
			if [ -z "$libclang_wheel" ]; then
				error "missing downloaded libclang wheel ${libclang_version}"
				build_rc=1
			else
				"${HOST_TOOLS_PYTHON}" -m zipfile -e "$libclang_wheel" "$libclang_extract_dir" || build_rc=$?
			fi
		fi
		if [ "$build_rc" -eq 0 ] && [ ! -f "${libclang_native_dir}/libclang.so" ]; then
			error "missing libclang.so in downloaded libclang wheel: ${libclang_native_dir}"
			build_rc=1
		fi
	fi
	if [ "$build_rc" -eq 0 ]; then
		export LD="${OHOS_LD_BINARY_INPUT_OR_CXX}"
		export LDXX="${OHOS_LD_BINARY_INPUT_OR_CXX}"
		export LLD="${OHOS_LD_BINARY_INPUT_OR_CXX}"
		export LIBCLANG_LIBRARY_PATH="${libclang_native_dir}"
		export PYMUPDF_SETUP_LIBCLANG="libclang==${libclang_version}"
		export PYCROSS_PYTHON_CONFIG_EXTRA_LDFLAGS="-L${gettext_prefix}/${OHOS_LIBDIR}"
		PYMUPDF_SETUP_SWIG="${HOST_SWIG}" build_python_cross_package_active -v --no-deps --no-binary :all: . || build_rc=$?
	fi
	export LD="${old_ld}"
	export LDXX="${old_ldxx}"
	export LLD="${old_lld}"
	export LDFLAGS="${old_ldflags}"
	if [[ "$old_libclang_library_path" == x* ]]; then
		export LIBCLANG_LIBRARY_PATH="${old_libclang_library_path#x}"
	else
		unset LIBCLANG_LIBRARY_PATH
	fi
	if [[ "$old_pymupdf_setup_libclang" == x* ]]; then
		export PYMUPDF_SETUP_LIBCLANG="${old_pymupdf_setup_libclang#x}"
	else
		unset PYMUPDF_SETUP_LIBCLANG
	fi
	export PYCROSS_PYTHON_CONFIG_EXTRA_LDFLAGS="${old_pycross_python_config_extra_ldflags}"
	destroy_pycrossenv || {
		[ "$build_rc" -eq 0 ] && build_rc=1
	}
	_custom_build_continue=false
	return "$build_rc"
}

post_configure_hook() {
	:
}

postbuilt_hook() {
	install_current_python_wheelhouse_to_target_site_packages
}

################ self-defined functions (local) goes below ################
