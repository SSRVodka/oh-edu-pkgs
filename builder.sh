#!/bin/bash

set -Eeuo pipefail

# Conventions
# - current_source_root: ${SRC_ROOT}/<pkgname>
# - target_root_with_pkgname: ${target_root_prefix_without_pkgname}.<pkgname>

info () { printf "%b%s%b" "\E[1;34m [NATIVE] ❯ \E[1;36m" "${1:-}" "\E[0m\n"; }
error () { printf "%b%s%b" "\E[1;31m [NATIVE] ❯ " "ERROR: ${1:-}" "\E[0m\n" >&2; }
warn () { printf "%b%s%b" "\E[1;33m [NATIVE] ❯ " "Warning: ${1:-}" "\E[0m\n" >&2; }

_custom_build_continue=true
_custom_download_source_continue=true
current_source_url=""
current=""
sources_root=""
current_source_root=""
target_root_with_pkgname=""
target_root_prefix_without_pkgname=""

native_project_root=$(dirname $(readlink -f $0))
native_sources_root=${native_project_root}/.staging.native
mkdir -p ${native_sources_root}


# Validation rules
validate_semver() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9]+)?(\+[a-zA-Z0-9]+)?$ ]]; }
validate_version() { [[ "$1" =~ ^[0-9]+(\.[0-9]+){0,2}(-[a-zA-Z0-9.]+)?(\+[a-zA-Z0-9.]+)?$ ]]; }
validate_url() { [[ "$1" =~ ^https?:// ]]; }
validate_no_space() { [[ ! "$1" =~ [[:space:]] ]]; }
validate_build_type() { [[ "$1" =~ ^(autotools|cmake|meson|pure-python|custom)$ ]]; }
validate_archs() {
    local IFS=','
    for arch in $1; do
        [[ "$arch" =~ ^(x86_64|aarch64|arm|riscv)$ ]] || return 1
    done
}

# Extract package names from comma-separated dependency string,
# stripping version constraints (e.g., >=1.0, <2.0, =3.0).
# Output: de-duplicated package names separated by space
get_pkg_names_from_deps() {
    # printf '%s' "${1:-}" | tr ',' '\n' | sed 's/[<>=].*//' | xargs
    printf '%s' "$1" |
        tr ',' '\n' |
        sed 's/[<>=].*//' |
        awk '!seen[$0]++' |
        xargs
}

# Get the source root directory (in staging area) of the specific package
# NOTE: it can ONLY be used in build_package
get_pkg_src_root() {
    printf '%s/%s' "${sources_root}" "${1:-}"
}

get_native_src_root() {
    printf '%s/%s' "${native_sources_root}" "${1:-}"
}

# Get the build output directory (in staging area) of the specific package
get_pkg_dst_dir() {
    printf '%s.%s' "${TARGET_ROOT}" "${1:-}"
}

# Move (merge) package $1 from $2 (default ${target_root_prefix_without_pkgname}, output internal directory) to ${target_root_with_pkgname}
mv_pkg_to_dst_dir() {
    local _pkg_name="${1:-}"
    local _pkg_src="${2:-${target_root_prefix_without_pkgname}}"
    local _pkg_dst="${target_root_with_pkgname}"
    if [ -d "$_pkg_dst" ]; then
        cp -r ${_pkg_src}/* ${_pkg_dst}/
        rm -rf ${_pkg_src}
    else
        mv ${_pkg_src} ${_pkg_dst}
    fi
}

# Variable definitions
PKG_VARS=(
    pkg_version pkg_name pkg_deps pkg_build_deps pkg_source_url pkg_release_url
    pkg_license pkg_support_archs pkg_build_type pkg_build_parallism
)

AUTOTOOLS_VARS=(
    pkg_build_autotools_extra_configure_flags pkg_build_autotools_bootstrap_script
    pkg_build_autotools_suffix_configure_flags pkg_build_autotools_configure_dir
)

CMAKE_VARS=(
    pkg_build_cmake_extra_cmake_flags pkg_build_cmake_extra_cmake_prefix_path
    pkg_build_cmake_extra_cflags pkg_build_cmake_extra_cppflags
    pkg_build_cmake_extra_ldflags pkg_build_cmake_extra_cmake_findroot_path
)

MESON_VARS=(
    pkg_build_meson_cross_file pkg_build_meson_extra_meson_flags
    pkg_build_meson_extra_cflags pkg_build_meson_extra_ldflags
    pkg_build_meson_extra_cmake_prefix_path pkg_build_meson_extra_cmake_findroot_path
)

clear_vars() {
    unset "${PKG_VARS[@]}" "${AUTOTOOLS_VARS[@]}" "${CMAKE_VARS[@]}" "${MESON_VARS[@]}" 2>/dev/null || true
}

save_xcompile_flags() {
    # record cross-compiling related flags
    # keep track with setup.sh
    _presetup_path=${PATH:-}
    _presetup_ld_libpath=${LD_LIBRARY_PATH:-}
    _presetup_cc=${CC:-}
    _presetup_cxx=${CXX:-}
    _presetup_as=${AS:-}
    _presetup_ld=${LD:-}
    _presetup_ldxx=${LDXX:-}
    _presetup_lld=${LLD:-}
    _presetup_strip=${STRIP:-}
    _presetup_ranlib=${RANLIB:-}
    _presetup_objdump=${OBJDUMP:-}
    _presetup_objcopy=${OBJCOPY:-}
    _presetup_readelf=${READELF:-}
    _presetup_nm=${NM:-}
    _presetup_ar=${AR:-}
    _presetup_profdata=${PROFDATA:-}
    _presetup_cflags=${CFLAGS:-}
    _presetup_cxxflags=${CXXFLAGS:-}
    _presetup_cppflags=${CPPFLAGS:-}
    _presetup_ldflags=${LDFLAGS:-}
    _presetup_ldshared=${LDSHARED:-}
    _presetup_pkg_config_path=${PKG_CONFIG_PATH:-}
    _presetup_pkg_config_libdir=${PKG_CONFIG_LIBDIR:-}
    _presetup_pkg_config_sysign=${PKG_CONFIG_SYSTEM_IGNORE_PATH:-}
}
restore_xcompile_flags() {
    # restore flags (failure prune: we've already setup trap in setup.sh)
    CC=$_presetup_cc
    CXX=$_presetup_cxx
    AS=$_presetup_as
    LD=$_presetup_ld
    LDXX=$_presetup_ldxx
    LLD=$_presetup_lld
    STRIP=$_presetup_strip
    RANLIB=$_presetup_ranlib
    OBJDUMP=$_presetup_objdump
    OBJCOPY=$_presetup_objcopy
    READELF=$_presetup_readelf
    NM=$_presetup_nm
    AR=$_presetup_ar
    PROFDATA=$_presetup_profdata
    CFLAGS=$_presetup_cflags
    CXXFLAGS=$_presetup_cxxflags
    CPPFLAGS=$_presetup_cppflags
    LDFLAGS=$_presetup_ldflags
    LDSHARED=$_presetup_ldshared
    PKG_CONFIG_PATH=$_presetup_pkg_config_path
    PKG_CONFIG_LIBDIR=$_presetup_pkg_config_libdir
    PKG_CONFIG_SYSTEM_IGNORE_PATH=$_presetup_pkg_config_sysign
}

validate_config() {
    local errors=0

    # Required field validations
    [[ -z "${pkg_version:-}" ]] && error "pkg_version is required" && ((errors++))
    [[ -n "${pkg_version:-}" ]] && ! validate_version "$pkg_version" && error "pkg_version must be valid version" && ((errors++))
    
    [[ -z "${pkg_name:-}" ]] && error "pkg_name is required" && ((errors++))
    [[ -n "${pkg_name:-}" ]] && ! validate_no_space "$pkg_name" && error "pkg_name cannot contain spaces" && ((errors++))
    
    [[ -z "${pkg_source_url:-}" && -z "${pkg_release_url:-}" ]] && error "pkg_source_url or pkg_release_url required" && ((errors++))
    [[ -n "${pkg_source_url:-}" ]] && ! validate_url "$pkg_source_url" && error "pkg_source_url invalid" && ((errors++))
    [[ -n "${pkg_release_url:-}" ]] && ! validate_url "$pkg_release_url" && error "pkg_release_url invalid" && ((errors++))
    
    [[ -z "${pkg_support_archs:-}" ]] && error "pkg_support_archs is required" && ((errors++))
    [[ -n "${pkg_support_archs:-}" ]] && ! validate_archs "$pkg_support_archs" && error "pkg_support_archs invalid" && ((errors++))
    
    [[ -z "${pkg_build_type:-}" ]] && error "pkg_build_type is required" && ((errors++))
    [[ -n "${pkg_build_type:-}" ]] && ! validate_build_type "$pkg_build_type" && error "pkg_build_type must be autotools, cmake, or meson" && ((errors++))
    
    [[ -n "${pkg_deps:-}" ]] && ! validate_no_space "$pkg_deps" && error "pkg_deps cannot contain spaces" && ((errors++))
    [[ -n "${pkg_build_deps:-}" ]] && ! validate_no_space "$pkg_build_deps" && error "pkg_build_deps cannot contain spaces" && ((errors++))

    return $errors
}

print_vars() {
    info "=== Package Configuration ==="
    for var in "${PKG_VARS[@]}"; do
        echo "$var: ${!var:-}"
    done

    case "${pkg_build_type:-}" in
        autotools)
            info "=== Autotools Configuration ==="
            for var in "${AUTOTOOLS_VARS[@]}"; do echo "$var: ${!var:-}"; done
            ;;
        cmake)
            info "=== CMake Configuration ==="
            for var in "${CMAKE_VARS[@]}"; do echo "$var: ${!var:-}"; done
            ;;
        meson)
            info "=== Meson Configuration ==="
            for var in "${MESON_VARS[@]}"; do echo "$var: ${!var:-}"; done
            ;;
    esac
    echo
}

wget_source() {
    url=${1:?usage: wget_source URL}
	output_dir=${2:?output_dir must be set}

    tmpf=$(mktemp) || { error "wget_source mktemp failed"; return 1; }
    tmpd=$(mktemp -d) || { error "wget_source mktemp -d failed"; rm -f "$tmpf"; return 1; }

    # Ensure cleanup on each failure/return without changing traps
    _cleanup() {
        rm -f -- "$tmpf"
        rm -rf -- "$tmpd"
    }

    # download
    if ! wget -O "$tmpf" -- "$url"; then
        error "wget_source download failed"
        _cleanup
        return 1
    fi

    # detect mime type (may be empty if file(1) not available; fallbacks below)
    mime=$(file -b --mime-type "$tmpf" 2>/dev/null || echo "")

    case "$mime" in
        application/zip)
            if ! unzip -q "$tmpf" -d "$tmpd"; then error "wget_source unzip failed"; _cleanup; return 1; fi
            ;;
        application/x-xz|application/x-7z-compressed)
            if ! tar -xJf "$tmpf" -C "$tmpd"; then error "wget_source tar -J failed"; _cleanup; return 1; fi
            ;;
        application/gzip|application/x-gzip)
            if ! tar -xzf "$tmpf" -C "$tmpd"; then error "wget_source tar -z failed"; _cleanup; return 1; fi
            ;;
        application/x-tar)
            if ! tar -xf "$tmpf" -C "$tmpd"; then error "wget_source tar failed"; _cleanup; return 1; fi
            ;;
        *)
            # fallback: try tar then unzip
            if tar -tf "$tmpf" >/dev/null 2>&1; then
                if ! tar -xf "$tmpf" -C "$tmpd"; then error "wget_source tar fallback failed"; _cleanup; return 1; fi
            elif unzip -t "$tmpf" >/dev/null 2>&1; then
                if ! unzip -q "$tmpf" -d "$tmpd"; then error "wget_source unzip fallback failed"; _cleanup; return 1; fi
            else
                error "wget_source unknown or unsupported archive format: '$mime'"
                _cleanup
                return 1
            fi
            ;;
    esac

    # list top-level entries (one-per-line). Note: this will break only for entries with embedded newlines.
    top_entries=$(find "$tmpd" -mindepth 1 -maxdepth 1 -print)
    count=$(printf '%s\n' "$top_entries" | sed -n '$=')

    if [ "$count" -ne 1 ]; then
        error "wget_source archive must contain exactly one top-level entry (found $count)"
        _cleanup
        return 1
    fi

    topdir=$(printf '%s\n' "$top_entries" | sed -n '1p')

    if [ ! -d "$topdir" ]; then
        error "wget_source top-level entry is not a directory"
        _cleanup
        return 1
    fi

    # move/rename top-level directory to desired name
	if [ -d "${output_dir}" ]; then
		# override
		rm -rf ${output_dir}
	fi
    if ! mv -- "$topdir" "${output_dir}"; then
        error "wget_source rename/move failed"
        _cleanup
        return 1
    fi

    # remove temp artefacts (tmpd may now be empty)
    _cleanup

    return 0
}

setup_pycrossenv() {
    local buildpy_libdir="${BUILD_PYTHON_DIST}/lib"
    if [[ ":${LD_LIBRARY_PATH:-}:" != *":${buildpy_libdir}:"* ]]; then
        export LD_LIBRARY_PATH=${buildpy_libdir}:$LD_LIBRARY_PATH
    fi
    # override the flags (python deps) in setup.sh
    local _pypkg_deps="$PY_DEPS python3"
    local dep
    for dep in $_pypkg_deps; do
        CFLAGS="-I$(get_pkg_dst_dir $dep)/include $CFLAGS"
        LDFLAGS="-L$(get_pkg_dst_dir $dep)/${OHOS_LIBDIR} $LDFLAGS"
        PKG_CONFIG_LIBDIR="$(get_pkg_dst_dir $dep)/${OHOS_LIBDIR}/pkgconfig:${PKG_CONFIG_LIBDIR}"
    done

    # add header path for special libraries (python deps & numpy-dev)
    CFLAGS="-I$(get_pkg_dst_dir xz)/include/lzma -I$(get_pkg_dst_dir libncursesw)/include/ncursesw -I$(get_pkg_dst_dir libreadline)/include/readline -I$(get_pkg_dst_dir util-linux)/include/uuid -I${NUMPY_LIBROOT}/include -I${NUMPY2_LIBROOT}/include $CFLAGS"
    CXXFLAGS="$CFLAGS"
    LDFLAGS="-lpython${PY_VERSION} -L${NUMPY_LIBROOT}/lib -L${NUMPY2_LIBROOT}/lib $LDFLAGS"
    PKG_CONFIG_LIBDIR="${HOST_PYTHON_DIST}/${OHOS_LIBDIR}/pkgconfig:${NUMPY_LIBROOT}/lib/pkgconfig:${NUMPY2_LIBROOT}/lib/pkgconfig"
    # export PKG_CONFIG_SYSROOT_DIR=${OHOS_SDK}/native/sysroot
    # export PKG_CONFIG_PATH=${HOST_PYTHON_DIST}/${OHOS_LIBDIR}/pkgconfig:${NUMPY_LIBROOT}/lib/pkgconfig
    # Use PKG_CONFIG_SYSTEM_IGNORE_PATH in setup.sh

    # setup flags in meson scripts
    for ms_sh in "${MESON_CROSS_ROOT}"/*.meson; do
        set_meson_list $ms_sh "common_c_flags" "$CFLAGS"
        set_meson_list $ms_sh "common_ld_flags" "$LDFLAGS"
    done

    # this will modify envs like PATH, _PS
    enter_pycrossenv
}

destroy_pycrossenv() {
    exit_pycrossenv
}

download() {
    
    _custom_download_source_continue=true
    custom_download_source || { warn "custom_download_source process for '$current_source_root' failed"; return 1; }
    if [ "x$_custom_download_source_continue" != "xtrue" ]; then
        return 0
    fi

    wget_source "${current_source_url}" "${current_source_root}" || { return 1; }
    # source downloaded to ${current_source_root}
}

build() {
    # assuming that source has been downloaded to ${current_source_root}
    # read $1 as current build file
    # read ${TARGET_ROOT} from setup.sh as output root + prefix without package name
    # read pkg_* from setup function executed before
    local current_build_file=${1:-}
    [[ ! -f "$current_build_file" ]] && error "BUILD file not found: $current_build_file" && return 1
    local current_build_file_dir=$(dirname $(readlink -f $current_build_file))

    local target="${pkg_name}"
    # parse build deps
    local deps_sep_space=$(get_pkg_names_from_deps "$pkg_build_deps")

    info "start building '$pkg_name' with deps: '$deps_sep_space'"

    # custom build process hook in BUILD
    _custom_build_continue=true
    custom_build || { warn "custom_build process for '$pkg_name' failed"; return 1; }
    if [ "x$_custom_build_continue" != "xtrue" ]; then
        info "skipping normal build process"
        return 0;
    fi

    pushd ${SRC_ROOT}

    case "x${pkg_build_type:-}" in
        xautotools)
            build_makeproj_with_deps \
                "$target" \
                "$deps_sep_space" \
                "$pkg_build_autotools_extra_configure_flags" \
                "$pkg_build_autotools_bootstrap_script" \
                "$pkg_build_autotools_suffix_configure_flags" \
                "$pkg_build_parallism" \
                "$pkg_build_autotools_configure_dir" \
            || { error "build_makeproj_with_deps failed"; return 1; }
            ;;
        xcmake)
            build_cmakeproj_with_deps \
                "$target" \
                "$deps_sep_space" \
                "$pkg_build_cmake_extra_cmake_flags" \
                "$pkg_build_cmake_extra_cmake_prefix_path" \
                "$pkg_build_cmake_extra_cflags" \
                "$pkg_build_cmake_extra_cppflags" \
                "$pkg_build_cmake_extra_ldflags" \
                "$pkg_build_parallism" \
                "$pkg_build_cmake_extra_cmake_findroot_path" \
                "ohos-build" \
            || { error "build_cmakeproj_with_deps failed"; return 1; }
            ;;
        xmeson)
            build_mesonproj_with_deps \
                "$target" \
                "$deps_sep_space" \
                "$pkg_build_meson_cross_file" \
                "$pkg_build_meson_extra_meson_flags" \
                "$pkg_build_parallism" \
                "$pkg_build_meson_extra_cflags" \
                "$pkg_build_meson_extra_ldflags" \
                "$pkg_build_meson_extra_cmake_prefix_path" \
                "$pkg_build_meson_extra_cmake_findroot_path" \
                "ohos-build" \
            || { error "build_mesonproj_with_deps failed"; return 1; }
            ;;
        xpure-python)
            pushd ${current_source_root}
            setup_pycrossenv
            pip install -v --no-binary :all: . || { error "pure-python pip build failed"; destroy_pycrossenv; popd; return 1; }
            destroy_pycrossenv
            popd
            ;;
        xcustom)
            info "user-defined custom build process finished"
            ;;
    esac

    popd
}

build_package() {
    local build_file="${1:-}"
    
    [[ ! -f "$build_file" ]] && error "BUILD file not found: $build_file" && return 1

    info "========================================"
    info "Processing: $build_file"
    info "========================================"

    clear_vars
    save_xcompile_flags
    
    source "$build_file"
    setup || { error "setup() failed"; restore_xcompile_flags; clear_vars; return 1; }
    validate_config || { restore_xcompile_flags; clear_vars; return 1; }
    
    # setup local variables for hooks
    current_source_url="$pkg_source_url"
    current="$(dirname $(readlink -f $build_file))"
    sources_root="${SRC_ROOT}"
    current_source_root="${SRC_ROOT}/${pkg_name}"
    target_root_prefix_without_pkgname="${TARGET_ROOT}"
    target_root_with_pkgname="$(get_pkg_dst_dir $pkg_name)"

    # download if ${current_source_root} doesn't exist
    if [ ! -d "${current_source_root}" ]; then
        download || { error "download for '$build_file' failed"; restore_xcompile_flags; clear_vars; return 1; }
    fi

    print_vars
    if [ ! -f "${current_source_root}/PATCHED_BY_OHLOHA" ]; then
        prebuilt_patch_once_hook || { error "prebuilt_patch_once_hook for '$build_file' failed"; restore_xcompile_flags; clear_vars; return 1; }
        touch "${current_source_root}/PATCHED_BY_OHLOHA"
    fi
    prebuilt_patch_hook || { error "prebuilt_patch_hook for '$build_file' failed"; restore_xcompile_flags; clear_vars; return 1; }
    build "$build_file" || { error "Build $build_file failed"; restore_xcompile_flags; clear_vars; return 1; }
    postbuilt_hook || { error "postbuilt_hook for '$build_file' failed"; restore_xcompile_flags; clear_vars; return 1; }

    # copy & trigger POSTINST script here: for installation at ${target_root_with_pkgname}
	for name in postinst POSTINST PostInst; do
		local postinst_path="${current}/${name}"
		if [ -f "$postinst_path" ]; then
			chmod u+x "$postinst_path"
            cp "$postinst_path" "${target_root_with_pkgname}/${name}"
			info "executing post installation script..."
			"$postinst_path" "${target_root_with_pkgname}" || true
			break
		fi
	done

    restore_xcompile_flags
    clear_vars
    info "Build $build_file completed"
    return 0
}

# NOTE: we will not resolve dependencies here! Make sure BUILD_FILEs are already topologically sorted
main() {
    local CONTINUE_ON_FAIL=false
    local OHOS_CPU_VALUE=""

    # parse simple options
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --continue-on-fail)
                CONTINUE_ON_FAIL=true
                shift
                ;;
            --cpu=*)
                OHOS_CPU_VALUE="${1#--cpu=}"
                shift
                ;;
            --)
                shift
                break
                ;;
            -*)
                echo "Unknown option: $1" >&2
                exit 2
                ;;
            *)
                break
                ;;
        esac
    done

    [[ $# -eq 0 ]] && echo "Usage: $0 [--continue-on-fail] [--cpu=aarch64|arm|x86_64] <BUILD_FILE> [BUILD_FILE...]" && exit 1

    # trigger presetup env hooks
    for build_file in "$@"; do
        LOAD_NATIVE_HOOK_ONLY=true source "$build_file"
        native_env_hook || { echo "fatal: native_env_hook failed"; exit 1; }
    done

    # Specify OHOS_CPU & OHOS_ARCH for setup.sh if --cpu was provided
    if [ -n "$OHOS_CPU_VALUE" ]; then
        export OHOS_CPU="$OHOS_CPU_VALUE"
        if [ "${OHOS_CPU}" = "aarch64" ]; then
            export OHOS_ARCH="arm64-v8a"
        elif [ "${OHOS_CPU}" = "arm" ]; then
            export OHOS_ARCH="armeabi-v7a"
        elif [ "${OHOS_CPU}" = "x86_64" ]; then
            export OHOS_ARCH="x86_64"
        else
            error "Unsupported cpu '$OHOS_CPU' (supported 'aarch64', 'arm', 'x86_64')"
            exit 1
        fi
    fi

    . setup2.sh

    info "Use OHOS_CPU=$OHOS_CPU, OHOS_ARCH=$OHOS_ARCH"

    local total=$# success=0 failed=0

    # for build_file in "$@"; do
    #     build_package "$build_file" && success=$((success + 1)) || failed=$((failed + 1))
    # done
    for build_file in "$@"; do
        if build_package "$build_file"; then
            success=$((success + 1))
        else
            failed=$((failed + 1))
            if [ "x$CONTINUE_ON_FAIL" != "xtrue" ]; then
                break
            fi
        fi
    done

    . cleanup.sh

    info "========================================"
    info "Build Summary"
    info "========================================"
    info "Total: $total | Success: $success | Failed: $failed"
    [[ $failed -gt 0 ]] && exit 1 || exit 0
}

main "$@"
