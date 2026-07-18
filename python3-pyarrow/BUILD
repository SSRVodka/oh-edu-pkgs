#!/bin/bash
set -Eeuo pipefail

setup() {
pkg_version="23.0.0"
pkg_name="python3-pyarrow"
pkg_deps="python3>3.7,python3-numpy>=2,arrow-cpp==23.0.0"
pkg_build_deps="python3>3.7,python3-numpy>=2,arrow-cpp==23.0.0"
pkg_source_url="https://github.com/apache/arrow/archive/refs/tags/apache-arrow-23.0.0.tar.gz"
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
pkg_patch_files="patches/${pkg_version}/0001-allow-cross-compile-numpy-include-dir.patch"
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
	pushd "${current_source_root}" >/dev/null || return 1
	apply_pkg_patches -p1 || { popd >/dev/null; return 1; }
	if ! grep -q "PYARROW_NUMPY_INCLUDE_DIR" "${current_source_root}/python/setup.py"; then
		echo "ERROR: pyarrow NumPy include cross-compile patch was not applied" >&2
		popd >/dev/null || true
		return 1
	fi
	popd >/dev/null || return 1
}

custom_build() {
	setup_pycrossenv
	"${PYCROSS_BUILD_PIP}" install "setuptools_scm[toml]>=8" || { destroy_pycrossenv; return 1; }
	export SETUPTOOLS_SCM_PRETEND_VERSION_FOR_PYARROW="${pkg_version}"

	# Arrow C++ built by arrow-cpp ohloha package (with Filesystem/JSON/Compute)
	local arrow_prefix=$(get_pkg_dst_dir arrow-cpp)
	local py_prefix=$(get_pkg_dst_dir python3)
	local np_prefix=$(get_pkg_dst_dir python3-numpy)
	export ARROW_HOME="${arrow_prefix}"
	export LD_LIBRARY_PATH="${arrow_prefix}/${OHOS_LIBDIR}:${LD_LIBRARY_PATH:-}"
	export PYARROW_BUNDLE_ARROW_CPP=1

	# Enable features that arrow-cpp provides
	export PYARROW_WITH_PARQUET=1
	export PYARROW_WITH_DATASET=1
	export PYARROW_WITH_ACERO=1
	export PYARROW_WITH_ORC=0
	export PYARROW_WITH_GANDIVA=0
	export PYARROW_WITH_PLASMA=0
	export PYARROW_WITH_FLIGHT=0
	export PYARROW_WITH_CSV=1
	export PYARROW_WITH_JSON=1
	export PYARROW_WITH_FILESYSTEM=1

	local numpy_inc="${np_prefix}/${OHOS_LIBDIR}/python${PY_VERSION}/site-packages/${NUMPY2_RELDIR}/include"
	export PYARROW_NUMPY_INCLUDE_DIR="${numpy_inc}"

	export PYARROW_CMAKE_OPTIONS="-DARROW_DEPENDENCY_SOURCE=AUTO \
		-DARROW_SIMD_LEVEL=NONE \
		-DPython3_NumPy_INCLUDE_DIR=${numpy_inc} \
		-DPython3_ROOT_DIR=${py_prefix} \
		-DCMAKE_PREFIX_PATH=${arrow_prefix} \
		-DArrow_DIR=${arrow_prefix}/${OHOS_LIBDIR}/cmake/Arrow"

	build_python_cross_package_active -v --no-deps --no-build-isolation --no-binary :all: ./python/ || { destroy_pycrossenv; return 1; }

	destroy_pycrossenv || { return 1; }
	_custom_build_continue=false
}

postbuilt_hook() {
	install_current_python_wheelhouse_to_target_site_packages
}

################ self-defined functions (local) goes below ################
