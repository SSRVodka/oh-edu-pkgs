#!/bin/bash
set -Eeuo pipefail

setup() {
pkg_version="23.0.0"
pkg_name="arrow-cpp"
pkg_deps=""
pkg_build_deps=""
pkg_source_url="https://github.com/apache/arrow/archive/refs/tags/apache-arrow-23.0.0.tar.gz"
pkg_release_url=""
pkg_license="Apache-2.0"
pkg_support_archs="x86_64,aarch64,arm"
pkg_build_type="cmake"
pkg_build_parallism=""
pkg_force_clean_build=""
pkg_patch_files="patches/${pkg_version}/0001-fix-ohos-bundled-boost-and-libatomic.patch"
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
	-DARROW_PARQUET=ON \
	-DARROW_DATASET=ON \
	-DARROW_ACERO=ON \
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
	-DARROW_DEPENDENCY_SOURCE=BUNDLED \
	-DBOOST_LOCALE_ENABLE=OFF"
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
	pushd "${current_source_root}"
	apply_pkg_patches -p1
	popd
}

custom_build() {
	export ARROW_UTF8PROC_URL="file://$(_cache_arrow_dependency \
		"https://github.com/JuliaStrings/utf8proc/archive/v2.10.0.tar.gz" \
		"utf8proc-v2.10.0.tar.gz" \
		"6f4f1b639daa6dca9f80bc5db1233e9cbaa31a67790887106160b33ef743f136")"
	export ARROW_RAPIDJSON_URL="file://$(_cache_arrow_dependency \
		"https://github.com/miloyip/rapidjson/archive/232389d4f1012dddec4ef84861face2d2ba85709.tar.gz" \
		"rapidjson-232389d4f1012dddec4ef84861face2d2ba85709.tar.gz" \
		"b9290a9a6d444c8e049bd589ab804e0ccf2b05dc5984a19ed5ae75d090064806")"
	export ARROW_RE2_URL="file://$(_cache_arrow_dependency \
		"https://github.com/google/re2/archive/2023-03-01.tar.gz" \
		"re2-2023-03-01.tar.gz" \
		"7a9a4824958586980926a300b4717202485c4b4115ac031822e29aa4ef207e48")"
	export ARROW_XSIMD_URL="file://$(_cache_arrow_dependency \
		"https://github.com/xtensor-stack/xsimd/archive/14.0.0.tar.gz" \
		"xsimd-14.0.0.tar.gz" \
		"17de0236954955c10c09d6938d4c5f3a3b92d31be5dadd1d5d09fc1b15490dce")"
	export ARROW_LZ4_URL="file://$(_cache_arrow_dependency \
		"https://github.com/lz4/lz4/archive/v1.10.0.tar.gz" \
		"lz4-v1.10.0.tar.gz" \
		"537512904744b35e232912055ccf8ec66d768639ff3abe5788d90d792ec5f48b")"
	export ARROW_ZSTD_URL="file://$(_cache_arrow_dependency \
		"https://github.com/facebook/zstd/releases/download/v1.5.7/zstd-1.5.7.tar.gz" \
		"zstd-1.5.7.tar.gz" \
		"eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3")"
	export ARROW_ZLIB_URL="file://$(_cache_arrow_dependency \
		"https://zlib.net/fossils/zlib-1.3.1.tar.gz" \
		"zlib-1.3.1.tar.gz" \
		"9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23")"
	export ARROW_THRIFT_URL="file://$(_cache_arrow_dependency \
		"https://archive.apache.org/dist/thrift/0.22.0/thrift-0.22.0.tar.gz" \
		"thrift-0.22.0.tar.gz" \
		"794a0e455787960d9f27ab92c38e34da27e8deeda7a5db0e59dc64a00df8a1e5")"
	export ARROW_BOOST_URL="file://$(_cache_arrow_dependency \
		"https://github.com/boostorg/boost/releases/download/boost-1.88.0/boost-1.88.0-cmake.tar.gz" \
		"boost-1.88.0-cmake.tar.gz" \
		"dcea50f40ba1ecfc448fdf886c0165cf3e525fef2c9e3e080b9804e8117b9694")"

	_custom_build_continue=true
}

postbuilt_hook() {
	:
}

################ self-defined functions (local) goes below ################

_download_arrow_dependency() {
	local url="${1:?dependency URL must be set}"
	local archive="${2:?dependency archive path must be set}"
	local expected_sha256="${3:?dependency SHA-256 must be set}"
	local source_archive tmp_archive

	[ -f "${archive}" ] && return 0
	mkdir -p "$(dirname "${archive}")"
	source_archive=$(source_archive_path_for_url "${url}") || return 1
	if [ -f "${source_archive}" ] &&
		[ "$(sha256_file "${source_archive}")" = "${expected_sha256}" ]; then
		cp "${source_archive}" "${archive}"
		return 0
	fi
	tmp_archive=$(mktemp "${archive}.tmp.XXXXXX") || return 1
	if ! wget -O "${tmp_archive}" -- "${url}"; then
		rm -f "${tmp_archive}"
		return 1
	fi
	if [ "$(sha256_file "${tmp_archive}")" != "${expected_sha256}" ]; then
		error "checksum mismatch for Arrow dependency: ${url}"
		rm -f "${tmp_archive}"
		return 1
	fi
	mv "${tmp_archive}" "${archive}"
}

_cache_arrow_dependency() {
	local url="${1:?dependency URL must be set}"
	local filename="${2:?dependency filename must be set}"
	local expected_sha256="${3:?dependency SHA-256 must be set}"
	local archive actual_sha256 url_digest

	archive="${download_cache_root}/${pkg_name}/${pkg_version}/${filename}"
	url_digest=$(printf '%s' "${url}" | sha256sum | awk '{print $1}')
	with_ohloha_lock "download-${url_digest}" \
		_download_arrow_dependency "${url}" "${archive}" "${expected_sha256}" || return 1
	actual_sha256=$(sha256_file "${archive}") || return 1
	if [ "${actual_sha256}" != "${expected_sha256}" ]; then
		error "cached checksum mismatch for Arrow dependency: ${url}"
		return 1
	fi
	printf '%s' "${archive}"
}
