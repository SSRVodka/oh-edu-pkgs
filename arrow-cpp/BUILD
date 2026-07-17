#!/bin/bash
set -Eeuo pipefail

setup() {
pkg_version="18.0.0"
pkg_name="arrow-cpp"
pkg_deps="libz>=1"
pkg_build_deps="libz>=1"
pkg_source_url="https://github.com/apache/arrow/archive/refs/tags/apache-arrow-18.0.0.tar.gz"
pkg_release_url=""
pkg_license="Apache-2.0"
pkg_support_archs="x86_64,aarch64,arm"
pkg_build_type="cmake"
pkg_build_parallism=""
pkg_force_clean_build=""
pkg_build_autotools_extra_configure_flags=""
pkg_build_autotools_bootstrap_script=""
pkg_build_autotools_suffix_configure_flags=""
pkg_build_autotools_configure_dir=""
pkg_build_autotools_make_install_target=""
pkg_build_cmake_extra_cmake_flags="-S cpp -G Ninja \
	-DARROW_BUILD_SHARED=ON \
	-DARROW_BUILD_STATIC=OFF \
	-DARROW_BUILD_TESTS=OFF \
	-DARROW_BUILD_EXAMPLES=OFF \
	-DARROW_BUILD_BENCHMARKS=OFF \
	-DARROW_BUILD_UTILITIES=OFF \
	-DARROW_JEMALLOC=OFF \
	-DARROW_MIMALLOC=OFF \
	-DARROW_COMPUTE=ON \
	-DARROW_CSV=ON \
	-DARROW_JSON=ON \
	-DARROW_FILESYSTEM=ON \
	-DARROW_IPC=ON \
	-DARROW_PARQUET=OFF \
	-DARROW_DATASET=OFF \
	-DARROW_ACERO=OFF \
	-DARROW_FLIGHT=OFF \
	-DARROW_FLIGHT_SQL=OFF \
	-DARROW_GANDIVA=OFF \
	-DARROW_PLASMA=OFF \
	-DARROW_ORC=OFF \
	-DARROW_WITH_ZLIB=ON \
	-DARROW_WITH_LZ4=ON \
	-DARROW_WITH_ZSTD=ON \
	-DARROW_WITH_SNAPPY=OFF \
	-DARROW_WITH_BROTLI=OFF \
	-DARROW_WITH_BZ2=OFF \
	-DARROW_SIMD_LEVEL=NONE \
	-DARROW_WITH_MUSL=ON \
	-DARROW_DEPENDENCY_SOURCE=BUNDLED"
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
	# Arrow C++ ExternalProject_Add downloads third-party deps at build time.
	# Pre-download all required deps to local file:// URLs to avoid network issues.
	local deps_dir="${native_project_root}/arrow-cpp/thirdparty-cache"
	mkdir -p "$deps_dir"

	# Download deps if not cached
	_download_dep() {
		local name="$1" url="$2"
		[ -f "$deps_dir/$name" ] && return 0
		curl -sSL -o "$deps_dir/$name" "$url" || true
	}

	_download_dep utf8proc-v2.7.0.tar.gz "https://github.com/JuliaStrings/utf8proc/archive/refs/tags/v2.7.0.tar.gz"
	_download_dep rapidjson-232389d4f1012dddec4ef84861face2d2ba85709.tar.gz "https://github.com/miloyip/rapidjson/archive/232389d4f1012dddec4ef84861face2d2ba85709.tar.gz"
	_download_dep re2-2022-06-01.tar.gz "https://github.com/google/re2/archive/refs/tags/2022-06-01.tar.gz"
	_download_dep xsimd-13.0.0.tar.gz "https://github.com/xtensor-stack/xsimd/archive/refs/tags/13.0.0.tar.gz"
	_download_dep lz4-v1.10.0.tar.gz "https://github.com/lz4/lz4/archive/refs/tags/v1.10.0.tar.gz"
	_download_dep zstd-1.5.6.tar.gz "https://github.com/facebook/zstd/releases/download/v1.5.6/zstd-1.5.6.tar.gz"
	_download_dep zlib-1.3.1.tar.gz "https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz"

	export ARROW_UTF8PROC_URL="file://${deps_dir}/utf8proc-v2.7.0.tar.gz"
	export ARROW_RAPIDJSON_URL="file://${deps_dir}/rapidjson-232389d4f1012dddec4ef84861face2d2ba85709.tar.gz"
	export ARROW_RE2_URL="file://${deps_dir}/re2-2022-06-01.tar.gz"
	export ARROW_XSIMD_URL="file://${deps_dir}/xsimd-13.0.0.tar.gz"
	export ARROW_LZ4_URL="file://${deps_dir}/lz4-v1.10.0.tar.gz"
	export ARROW_ZSTD_URL="file://${deps_dir}/zstd-1.5.6.tar.gz"
	export ARROW_ZLIB_URL="file://${deps_dir}/zlib-1.3.1.tar.gz"

	_custom_build_continue=true
}

postbuilt_hook() {
	:
}

################ self-defined functions (local) goes below ################
