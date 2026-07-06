#!/bin/bash
set -Eeuo pipefail

setup() {
pkg_version="1.7.1"
pkg_name="python3-evdev"
pkg_deps="python3>3.7"
pkg_build_deps="python3>3.7"
pkg_source_url="https://files.pythonhosted.org/packages/source/e/evdev/evdev-1.7.1.tar.gz"
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

	local build_rc=0
	setup_pycrossenv || return 1

	# evdev generates ecodes.c from Linux kernel headers at build time via
	# genecodes.py. Point build_ecodes --evdev-headers to the OH SDK sysroot
	# headers. Some newer keycode macros are missing from the SDK header; patch
	# a workdir-local copy instead of writing to the SDK sysroot.
	local sysroot_inc="${OHOS_SDK}/native/sysroot/usr/include/linux"
	local evdev_header_root="${current_source_root}/ohloha-build/evdev-headers/linux"
	local evdev_header_include="${current_source_root}/ohloha-build/evdev-headers"
	local evdev_headers="${evdev_header_root}/input.h:${evdev_header_root}/input-event-codes.h"

	mkdir -p "${evdev_header_root}"
	cp "${sysroot_inc}/input.h" "${evdev_header_root}/input.h"
	cp "${sysroot_inc}/input-event-codes.h" "${evdev_header_root}/input-event-codes.h"
	if ! grep -q 'KEY_ALL_APPLICATIONS' "${evdev_header_root}/input-event-codes.h" 2>/dev/null; then
		cat >> "${evdev_header_root}/input-event-codes.h" << 'KEYEOF'
/* Added by ohloha for newer kernel keycodes */
#define KEY_ALL_APPLICATIONS   0x2a4
#define KEY_LINK_PHONE         0x2a6
#define KEY_REFRESH_RATE_TOGGLE 0x2a7
#define KEY_EMOJI_PICKER       0x2a9
#define KEY_DICTATE            0x2aa
KEYEOF
	fi
	CFLAGS="-I${evdev_header_include} ${CFLAGS:-}"
	CPPFLAGS="-I${evdev_header_include} ${CPPFLAGS:-}"
	export CFLAGS CPPFLAGS

	pushd "${current_source_root}"
	"${PYCROSS_CROSS_PYTHON}" setup.py build_ecodes --evdev-headers "${evdev_headers}" || build_rc=$?
	popd || {
		[ "$build_rc" -eq 0 ] && build_rc=1
	}
	if [ "$build_rc" -eq 0 ]; then
		build_python_cross_package_active -v --no-binary :all: --no-build-isolation . || build_rc=$?
	fi

	destroy_pycrossenv || {
		[ "$build_rc" -eq 0 ] && build_rc=1
	}
	_custom_build_continue=false
	return "$build_rc"
}

postbuilt_hook() {
	install_current_python_wheelhouse_to_target_site_packages
}

################ self-defined functions (local) goes below ################
