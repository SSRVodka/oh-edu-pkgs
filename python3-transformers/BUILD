#!/bin/bash
set -Eeuo pipefail

setup() {

pkg_version="5.12.1"
pkg_name="python3-transformers"
pkg_deps="python3>3.7,python3-regex,python3-tokenizers"
pkg_build_deps="python3>3.7,python3-build,python3-wheel,python3-setuptools"
pkg_source_url="https://files.pythonhosted.org/packages/source/t/transformers/transformers-5.12.1.tar.gz"
pkg_release_url=""
pkg_license="Apache-2.0"
pkg_support_archs="x86_64,aarch64,arm"
pkg_build_type="pure-python"
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
	:
}

################ self-defined functions (local) goes below ################
