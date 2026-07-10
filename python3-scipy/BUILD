#!/bin/bash
set -Eeuo pipefail

setup() {

pkg_version="1.18.0"
pkg_name="python3-scipy"
pkg_deps="python3>=3.12,python3-numpy>=2,<2.8,openblas"
pkg_build_deps="python3>=3.12,python3-numpy>=2,<2.8,openblas,python3-build,python3-setuptools,python3-cython"
pkg_source_url="https://files.pythonhosted.org/packages/a7/25/c2700dfaf6442b4effaa91af24ebce5dc9d31bb4a69706313aae70d72cd0/scipy-1.18.0.tar.gz"
pkg_release_url=""
pkg_license="MIT"
pkg_support_archs="x86_64,aarch64"
pkg_build_type="custom"
pkg_build_parallism="20"
pkg_force_clean_build=""
pkg_patch_files="patches/${pkg_version}/0001-duccfft-disable-pthread-affinity-on-ohos.patch"

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
	apply_pkg_git_patches || return 1
}

custom_build() {
	local build_rc=0
	setup_pycrossenv || return 1

	"${PYCROSS_BUILD_PIP}" install meson-python "Cython>=3.2.0,<3.3.0" "pybind11>=2.13.2,<3.1.0" "pythran>=0.18.1,<0.19.0" || build_rc=$?
	if [ "$build_rc" -eq 0 ]; then
		local meson_cross="${MESON_CROSS_ROOT}/scipy-build.numpy2.meson"
		if [ ! -f "$meson_cross" ]; then
			meson_cross="${MESON_CROSS_ROOT}/ohos-build.meson"
		fi
		local python_prefix
		python_prefix=$(get_pkg_dst_dir python3) || build_rc=$?
		local dep dep_prefix
		for dep in $(get_pkg_names_from_deps "$pkg_deps"); do
			case "$dep" in
				python3|python3-*) continue ;;
			esac
			dep_prefix=$(get_pkg_dst_dir "$dep") || build_rc=$?
			if [ "$build_rc" -eq 0 ]; then
				CFLAGS="-I${dep_prefix}/include ${CFLAGS}"
				CXXFLAGS="${CFLAGS}"
				CPPFLAGS="${CFLAGS}"
				LDFLAGS="-L${dep_prefix}/${OHOS_LIBDIR} ${LDFLAGS}"
				PKG_CONFIG_LIBDIR="${dep_prefix}/${OHOS_LIBDIR}/pkgconfig:${PKG_CONFIG_LIBDIR}"
			fi
		done
		local gfortran_rt_dir="${native_project_root}/patches/libgfortran_rt/${OHOS_CPU}"
		if [ "$build_rc" -eq 0 ] && [ ! -d "$gfortran_rt_dir" ]; then
			error "missing libgfortran runtime for ${OHOS_CPU}: $gfortran_rt_dir"
			build_rc=1
		fi
		if [ "$build_rc" -eq 0 ] && ! command -v "${OHOS_CPU}-linux-gnu-gfortran" >/dev/null 2>&1; then
			error "missing Fortran compiler: ${OHOS_CPU}-linux-gnu-gfortran"
			build_rc=1
		fi
		if [ "$build_rc" -eq 0 ]; then
			local meson_ldflags="${LDFLAGS}"
			meson_ldflags="-L${python_prefix}/${OHOS_LIBDIR} ${meson_ldflags}"
			set_meson_list "$meson_cross" "common_c_flags" "$CFLAGS"
			set_meson_list "$meson_cross" "common_ld_flags" "$meson_ldflags"
			build_python_cross_package_active -v --no-deps --no-build-isolation --no-binary :all: -Csetup-args="--cross-file=$meson_cross" . || build_rc=$?
		fi
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
	local gfortran_rt_dir="${native_project_root}/patches/libgfortran_rt/${OHOS_CPU}"
	if [ -d "$gfortran_rt_dir" ]; then
		mkdir -p "${target_root_with_pkgname}/${OHOS_LIBDIR}"
		cp -a "$gfortran_rt_dir"/. "${target_root_with_pkgname}/${OHOS_LIBDIR}/"
	fi
}

################ self-defined functions (local) goes below ################
