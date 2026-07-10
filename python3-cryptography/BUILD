#!/bin/bash
set -Eeuo pipefail

setup() {

pkg_version="49.0.0"
pkg_name="python3-cryptography"
pkg_deps="python3>=3.9,python3-cffi>=2.0.0,openssl>=3.0"
pkg_build_deps="python3>=3.9,python3-cffi>=2.0.0,openssl>=3.0,python3-build,python3-setuptools"
pkg_source_url="https://files.pythonhosted.org/packages/1f/99/d1c90d6041656cc6ee229dc99cd67fd0cd5aec3c5f7d72fffc27cc750054/cryptography-49.0.0.tar.gz"
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
	setup_pycrossenv || return 1

	"${PYCROSS_BUILD_PIP}" install "cffi>=2.0.0" "maturin>=1.9.4,<2,!=1.12.0" || build_rc=$?
	if [ "$build_rc" -eq 0 ]; then
		local openssl_prefix
		openssl_prefix=$(get_pkg_dst_dir openssl) || build_rc=$?
		CFLAGS="-I${openssl_prefix}/include ${CFLAGS}"
		LDFLAGS="-L${openssl_prefix}/${OHOS_LIBDIR} ${LDFLAGS}"
		PKG_CONFIG_LIBDIR="${openssl_prefix}/${OHOS_LIBDIR}/pkgconfig:${PKG_CONFIG_LIBDIR}"
		export OPENSSL_DIR="${openssl_prefix}"
		setup_pyo3_rust_cross_env || build_rc=$?
	fi
	if [ "$build_rc" -eq 0 ]; then
		build_python_cross_package_active -v --no-deps --no-build-isolation --no-binary :all: . || build_rc=$?
	fi

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
