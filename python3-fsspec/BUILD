#!/bin/bash
set -Eeuo pipefail

setup() {
pkg_version="2026.6.0"
pkg_name="python3-fsspec"
pkg_deps="python3>=3.10"
pkg_build_deps="python3>=3.10,python3-build,python3-setuptools"
pkg_source_url="https://files.pythonhosted.org/packages/10/a1/ae4e3e5003468d6391d2c77b6fa1cd73bd5d13511d81c642d7b28ac90ed4/fsspec-2026.6.0.tar.gz"
pkg_release_url=""
pkg_license="BSD-3-Clause"
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
