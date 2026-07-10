#!/bin/bash
set -Eeuo pipefail

setup() {

pkg_version="18.0.0"
pkg_name="python3-av"
pkg_deps="python3>=3.11,ffmpeg>=8"
pkg_build_deps="python3>=3.11,ffmpeg>=8,python3-build,python3-setuptools,python3-cython"
pkg_source_url="https://files.pythonhosted.org/packages/ae/a4/570a5a35c8638aba01e739925846c35fdd6b0756a15526766d0a4dd3b7df/av-18.0.0.tar.gz"
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

	"${PYCROSS_BUILD_PIP}" install "cython>=3.1.0,<4" || build_rc=$?

	local dep dep_prefix
	for dep in $(get_pkg_names_from_deps "$pkg_deps"); do
		case "$dep" in
			python3|python3-*) continue ;;
		esac
		dep_prefix=$(get_pkg_dst_dir "$dep") || build_rc=$?
		if [ "$build_rc" -eq 0 ]; then
			CFLAGS="-I${dep_prefix}/include ${CFLAGS}"
			LDFLAGS="-L${dep_prefix}/${OHOS_LIBDIR} ${LDFLAGS}"
			PKG_CONFIG_LIBDIR="${dep_prefix}/${OHOS_LIBDIR}/pkgconfig:${PKG_CONFIG_LIBDIR}"
		fi
	done

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
