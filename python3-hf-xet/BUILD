#!/bin/bash
set -Eeuo pipefail

setup() {
pkg_version="1.5.1"
pkg_name="python3-hf-xet"
pkg_deps="python3>=3.8"
pkg_build_deps="python3>=3.8"
pkg_source_url="https://files.pythonhosted.org/packages/4b/2d/57fd21d84d93efb4bd0b962383790e19dd1bc053501b4264c97903b4e83e/hf_xet-1.5.1.tar.gz"
pkg_release_url=""
pkg_license="Apache-2.0"
pkg_support_archs="x86_64,aarch64,arm"
pkg_build_type="pyo3-rust"
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
	local build_rc=0
	local pushed=false
	local saved_ldflags="${LDFLAGS:-}"
	local wheel_dir="${current_work_root}/wheels/${pkg_name}"
	local -a wheels=()

	setup_pyo3_rust_cross_env || return 1
	export LDFLAGS="$saved_ldflags"

	current_python_wheelhouse="$wheel_dir"
	rm -rf "$wheel_dir"
	mkdir -p "$wheel_dir" || build_rc=$?

	if [ "$build_rc" -eq 0 ]; then
		pushd "${current_source_root}" >/dev/null || build_rc=$?
	fi
	if [ "$build_rc" -eq 0 ]; then
		pushed=true
		"${HOST_MATURIN}" build \
			--interpreter "${PYO3_PYTHON}" \
			--target "${CARGO_BUILD_TARGET}" \
			--release \
			--skip-auditwheel \
			--out "$wheel_dir" \
			|| build_rc=$?
	fi

	if [ "$build_rc" -eq 0 ]; then
		mapfile -t wheels < <(find "$wheel_dir" -maxdepth 1 -type f -name "*.whl" | sort)
		if [ "${#wheels[@]}" -eq 0 ]; then
			error "pyo3-rust build did not produce a wheel"
			build_rc=1
		else
			archive_python_wheels "$wheel_dir" || build_rc=$?
		fi
	fi

	if [ "$pushed" = true ]; then
		popd >/dev/null || {
			[ "$build_rc" -eq 0 ] && build_rc=1
		}
	fi
	destroy_pyo3_rust_cross_env || {
		[ "$build_rc" -eq 0 ] && build_rc=1
	}

	_custom_build_continue=false
	return "$build_rc"
}
post_configure_hook() { :; }
postbuilt_hook() { install_current_python_wheelhouse_to_target_site_packages; }
