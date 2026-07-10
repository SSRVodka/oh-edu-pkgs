#!/bin/bash
set -Eeuo pipefail

setup() {

pkg_version="3.11.0"
pkg_name="python3-matplotlib"
pkg_deps="python3>=3.11,python3-contourpy>=1.0.1,python3-cycler>=0.10,python3-fonttools>=4.22.0,python3-kiwisolver>=1.3.1,python3-numpy>=2,<2.8,python3-packaging>=20.0,python3-pillow>=9,python3-pyparsing>=3,python3-python-dateutil>=2.7"
pkg_build_deps="python3>=3.11,python3-contourpy>=1.0.1,python3-cycler>=0.10,python3-fonttools>=4.22.0,python3-kiwisolver>=1.3.1,python3-numpy>=2,<2.8,python3-packaging>=20.0,python3-pillow>=9,python3-pyparsing>=3,python3-python-dateutil>=2.7,python3-build,python3-setuptools,python3-cython"
pkg_source_url="https://files.pythonhosted.org/packages/1f/24/080c99d223d158d3a8902769269ab6da5b50f7a0e6e072513907e02b7a6c/matplotlib-3.11.0.tar.gz"
pkg_release_url=""
pkg_license="Apache-2.0"
pkg_support_archs="x86_64,aarch64,arm"
pkg_build_type="custom"
pkg_build_parallism="20"
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

	"${PYCROSS_BUILD_PIP}" install meson-python "pybind11>=2.13.2" "setuptools-scm>=7,<10" || build_rc=$?
	if [ "$build_rc" -eq 0 ]; then
		local meson_cross="${MESON_CROSS_ROOT}/scipy-build.numpy2.meson"
		local python_prefix
		python_prefix=$(get_pkg_dst_dir python3) || build_rc=$?
		if [ ! -f "$meson_cross" ]; then
			meson_cross="${MESON_CROSS_ROOT}/ohos-build.meson"
		fi
		if [ "$build_rc" -eq 0 ]; then
			set_meson_list "$meson_cross" "common_c_flags" "$CFLAGS"
			set_meson_list "$meson_cross" "common_ld_flags" "-L${python_prefix}/${OHOS_LIBDIR} ${LDFLAGS}"
			build_python_cross_package_active -v --no-deps --no-build-isolation --no-binary :all: -Csetup-args="--cross-file=$meson_cross" . || build_rc=$?
		fi
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
