#!/bin/bash
set -Eeuo pipefail

setup() {
pkg_version="0.22.2"
pkg_name="python3-tokenizers"
pkg_deps="python3>3.7"
pkg_build_deps="python3>3.7"
pkg_source_url="https://files.pythonhosted.org/packages/source/t/tokenizers/tokenizers-0.22.2.tar.gz"
pkg_release_url=""
pkg_license="Apache-2.0"
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
	export PATH="${HOME}/.cargo/bin:${PATH}"
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
	# tokenizers is a Rust+Python hybrid built with maturin (PyO3).
	# Rust/cc-rs/PyO3 cross-compile env vars are set centrally in
	# setup2.sh's setup_rust_cross_compile() (called by setup_pycrossenv).

	export PATH="${HOME}/.cargo/bin:${PATH}"
	rustup target add aarch64-unknown-linux-musl 2>/dev/null || true
	pip install maturin 2>/dev/null || true

	setup_pycrossenv

	pushd ${current_source_root}
	export MATURIN_NO_WHEEL_REPAIR=1
	maturin build --interpreter "${PYO3_PYTHON}" --target aarch64-unknown-linux-musl --release --skip-auditwheel

	# Extract the wheel manually (host pip can't install musllinux wheels)
	local wheel_file=$(find ${current_source_root} -name "*.whl" -path "*/wheels/*" 2>/dev/null | head -1)
	if [ -n "${wheel_file}" ]; then
		echo "Found wheel: ${wheel_file}"
		local extract_dir="${current_source_root}/wheel_extracted"
		rm -rf "${extract_dir}" && mkdir -p "${extract_dir}"
		python3 -m zipfile -e "${wheel_file}" "${extract_dir}"
		local site_pkgs="${HOST_SITE_PKGS}"
		cp -r "${extract_dir}/tokenizers" "${site_pkgs}/"
		cp -r ${extract_dir}/tokenizers-*.dist-info "${site_pkgs}/"
	else
		echo "ERROR: No wheel found after maturin build"
		exit 1
	fi
	popd

	destroy_pycrossenv
	_custom_build_continue=false
}

postbuilt_hook() {
	local out=${target_root_with_pkgname}/${OHOS_LIBDIR}/python${PY_VERSION}/site-packages
	mkdir -p ${out}
	cp -r ${HOST_SITE_PKGS}/tokenizers* ${out}/
}

################ self-defined functions (local) goes below ################
