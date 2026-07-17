#!/bin/bash
set -Eeuo pipefail

setup() {
pkg_version="0.24.2"
pkg_name="python3-wandb"
pkg_deps="python3>3.7"
pkg_build_deps="python3>3.7"
pkg_source_url="https://github.com/wandb/wandb/archive/refs/tags/v0.24.2.tar.gz"
pkg_release_url=""
pkg_license="MIT"
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

prebuilt_patch_once_hook() {
	_wandb_patch_hatch_build
}

prebuilt_patch_hook() {
	:
}

_wandb_patch_hatch_build() {
	# hatch_build.py builds two native binaries via _prepare_wheel:
	# 1. wandb-core (Go) — requires Go toolchain, not available in cross-compile
	# 2. gpu_stats (Rust) — uses cargo, can be cross-compiled
	# Patch _prepare_wheel to skip Go build but keep Rust build.
	local hb="${current_source_root:-.}/hatch_build.py"
	[ -f "$hb" ] || return 0
	grep -q 'patched by ohloha' "$hb" && return 0
	sed -i '/def _build_wandb_core/,/return \[output.as_posix()\]/{
		s/return \[output.as_posix()\]/return []  # patched by ohloha: skip Go build/
	}' "$hb"
}

custom_build() {

	# Set up Rust cross-compile env for gpu_stats (cargo build)
	setup_pyo3_rust_cross_env || true

	build_python_cross_package_active -v --no-deps --no-binary :all: .

	destroy_pyo3_rust_cross_env || true
	_custom_build_continue=false
}

postbuilt_hook() {
	install_current_python_wheelhouse_to_target_site_packages
}

################ self-defined functions (local) goes below ################

