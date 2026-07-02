#!/bin/bash
set -Eeuo pipefail

setup() {

pkg_version="0.5.3"
pkg_name="python3-safetensors"
pkg_deps="python3>3.7"
pkg_build_deps="python3>3.7"
pkg_source_url="https://files.pythonhosted.org/packages/source/s/safetensors/safetensors-0.5.3.tar.gz"
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
	export PATH="${HOME}/.cargo/bin:${PATH}"
	rustup target add aarch64-unknown-linux-musl 2>/dev/null || true
	pip install maturin 2>/dev/null || true

	setup_pycrossenv

	local ohos_sysroot="${OHOS_SDK}/native/sysroot"
	local ohos_cc="${OHOS_SDK}/native/llvm/bin/clang"
	local ohos_cxx_inc="${OHOS_SDK}/native/llvm/include/libcxx-ohos/include/c++/v1"

	export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER="${ohos_cc}"
	export RUSTFLAGS="-C linker=${ohos_cc} \
		-C link-arg=--target=aarch64-linux-ohos \
		-C link-arg=--sysroot=${ohos_sysroot} \
		-C link-arg=-lpython${PY_VERSION}"

	export CC_aarch64_unknown_linux_musl="${ohos_cc}"
	export CXX_aarch64_unknown_linux_musl="${OHOS_SDK}/native/llvm/bin/clang++"
	export CRATE_CC_NO_DEFAULTS=1
	export CFLAGS_aarch64_unknown_linux_musl="--target=aarch64-linux-ohos --sysroot=${ohos_sysroot} -I${ohos_cxx_inc}"
	export CXXFLAGS_aarch64_unknown_linux_musl="--target=aarch64-linux-ohos --sysroot=${ohos_sysroot} -I${ohos_cxx_inc} -std=c++17"
	export CXXSTDLIB="c++"

	local host_python=$(which python3)
	export PYO3_PYTHON="${host_python}"
	export PYO3_CROSS_PYTHON_VERSION="${PY_VERSION}"
	export PYO3_CROSS_LIB_DIR="${HOST_PYTHON_DIST}/lib"
	export PYO3_CROSS_INCLUDE_DIR="${HOST_PYTHON_DIST}/include/python${PY_VERSION}"

	# libgcc_s stub (OH uses libunwind)
	echo "" | ${OHOS_SDK}/native/llvm/bin/llvm-ar rcs ${ohos_sysroot}/usr/lib/aarch64-linux-ohos/libgcc_s.a 2>/dev/null || true

	pushd ${current_source_root}
	export MATURIN_NO_WHEEL_REPAIR=1
	maturin build --interpreter "${host_python}" --target aarch64-unknown-linux-musl --release --skip-auditwheel

	local wheel_file=$(find ${current_source_root} -name "*.whl" -path "*/wheels/*" 2>/dev/null | head -1)
	if [ -n "${wheel_file}" ]; then
		local extract_dir="${current_source_root}/wheel_extracted"
		rm -rf "${extract_dir}" && mkdir -p "${extract_dir}"
		python3 -m zipfile -e "${wheel_file}" "${extract_dir}"
		local site_pkgs="${HOST_SITE_PKGS}"
		cp -r "${extract_dir}/safetensors" "${site_pkgs}/"
		local dist_info=$(ls -d "${extract_dir}/safetensors-*.dist-info" 2>/dev/null | head -1)
		if [ -n "${dist_info}" ]; then
			cp -r "${dist_info}" "${site_pkgs}/"
		fi
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
	cp -r ${HOST_SITE_PKGS}/safetensors* ${out}/
}

################ self-defined functions (local) goes below ################
