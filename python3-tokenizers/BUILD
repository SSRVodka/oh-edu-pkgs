#!/bin/bash
set -Eeuo pipefail

setup() {
pkg_version="0.22.2"
pkg_name="python3-tokenizers"
pkg_deps="python3>3.7"
pkg_build_deps="python3>3.7"
pkg_source_url="https://files.pythonhosted.org/packages/source/t/tokenizers/tokenizers-0.22.2.tar.gz"
pkg_release_url=""
pkg_license="Apache-2.0"
pkg_support_archs="x86_64,aarch64,arm"
pkg_build_type="pyo3-rust"
pkg_build_parallism=""
pkg_force_clean_build=""
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
	_custom_build_continue=true
}

postbuilt_hook() {
	local wheel_dir="${current_python_wheelhouse:-}"
	local out="${target_root_with_pkgname}/${OHOS_LIBDIR}/python${PY_VERSION}/site-packages"
	local wheel

	[ -d "$wheel_dir" ] || { echo "ERROR: missing wheelhouse: ${wheel_dir}"; return 1; }
	mkdir -p "$out" || return 1
	for wheel in "$wheel_dir"/*.whl; do
		[ -f "$wheel" ] || { echo "ERROR: no wheel in ${wheel_dir}"; return 1; }
		"${HOST_TOOLS_PYTHON}" -m zipfile -e "$wheel" "$out" || return 1
	done
}

################ self-defined functions (local) goes below ################
