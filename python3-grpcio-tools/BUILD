#!/bin/bash
set -Eeuo pipefail

setup() {

pkg_version="1.78.1"
pkg_name="python3-grpcio-tools"
pkg_deps="python3>=3.9,python3-grpcio>=1.78.1,python3-protobuf>=6.31.1,<7.0.0,python3-setuptools>=77.0.1"
pkg_build_deps="python3>=3.9,python3-grpcio>=1.78.1,python3-protobuf>=6.31.1,<7.0.0,python3-setuptools>=77.0.1,grpc,python3-build,python3-cython"
pkg_source_url="https://github.com/grpc/grpc"
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
	mkdir -p "${current_source_root}"
	_custom_download_source_continue=false
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
	_custom_build_continue=false
}

post_configure_hook() {
	:
}

postbuilt_hook() {
	install_grpc_wheel_to_target_site_packages "grpcio_tools-*.whl"
}

################ self-defined functions (local) goes below ################

install_grpc_wheel_to_target_site_packages() {
	local wheel_pattern="${1:-}"
	local grpc_prefix
	local grpc_wheel_dir
	local package_wheel_dir="${current_work_root}/wheels/${pkg_name}"
	local -a wheels=()

	[ -n "$wheel_pattern" ] || { error "empty grpc wheel pattern"; return 1; }
	grpc_prefix=$(get_pkg_dst_dir grpc) || return 1
	grpc_wheel_dir="${grpc_prefix}/python-wheels"
	[ -d "$grpc_wheel_dir" ] || { error "missing grpc python wheelhouse: ${grpc_wheel_dir}"; return 1; }
	mapfile -t wheels < <(find "$grpc_wheel_dir" -maxdepth 1 -type f -name "$wheel_pattern" | sort)
	if [ "${#wheels[@]}" -ne 1 ]; then
		error "expected exactly one ${wheel_pattern} in ${grpc_wheel_dir}, found ${#wheels[@]}"
		return 1
	fi
	rm -rf "$package_wheel_dir"
	mkdir -p "$package_wheel_dir" || return 1
	cp -f "${wheels[0]}" "$package_wheel_dir/" || return 1
	install_python_wheelhouse_to_target_site_packages "$package_wheel_dir"
}
