#!/bin/bash
set -Eeuo pipefail

setup() {
pkg_version="3.29.7"
pkg_name="python3-filelock"
pkg_deps="python3>=3.10"
pkg_build_deps="python3>=3.10,python3-build,python3-setuptools"
pkg_source_url="https://files.pythonhosted.org/packages/35/94/00f2059e4835eace3ae8fde680b932c496f8ec7bdc99168dfa53fb2e6b79/filelock-3.29.7.tar.gz"
pkg_release_url=""
pkg_license="Unlicense"
pkg_support_archs="x86_64,aarch64,arm"
pkg_build_type="pure-python"
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

native_env_hook() { :; }
custom_download_source() { _custom_download_source_continue=true; }
if [ "x${LOAD_NATIVE_HOOK_ONLY:-}" = "xtrue" ]; then return 0; fi
prebuilt_patch_hook() { :; }
prebuilt_patch_once_hook() { :; }
custom_build() {
	build_python_cross_package -v --no-deps . || return 1
	_custom_build_continue=false
}
post_configure_hook() { :; }
postbuilt_hook() { install_current_python_wheelhouse_to_target_site_packages; }
