#!/bin/bash
set -Eeuo pipefail

setup() {

pkg_version="0.16.2"
pkg_name="python3-pyzstd"
pkg_deps="python3>3.7,zstd"
pkg_build_deps="python3>3.7,zstd"
pkg_source_url="https://files.pythonhosted.org/packages/source/p/pyzstd/pyzstd-0.16.2.tar.gz"
pkg_release_url=""
pkg_license="BSD-3-Clause"
pkg_support_archs="x86_64,aarch64,arm"
pkg_build_type="custom"
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

	setup_pycrossenv

	# pyzstd uses cffi to bind against system libzstd at build time.
	# Point cffi to the ohloha-built zstd headers and library.
	local zstd_prefix="$(get_pkg_dst_dir zstd)"
	export PYZSTD_INSTALL_PREFIX="${zstd_prefix}/usr"

	pushd ${current_source_root}
	pip install -v --no-binary :all: .
	popd

	destroy_pycrossenv
	_custom_build_continue=false
}

postbuilt_hook() {
	local out=${target_root_with_pkgname}/${OHOS_LIBDIR}/python${PY_VERSION}/site-packages
	mkdir -p ${out}
	cp -r ${HOST_SITE_PKGS}/pyzstd* ${out}/
}

################ self-defined functions (local) goes below ################
