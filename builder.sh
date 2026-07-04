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
current_build_root=""
target_root_with_pkgname=""
target_root_prefix_without_pkgname=""
current_source_fresh=false
current_work_root=""

native_project_root=$(dirname "$(readlink -f "$0")")
ohloha_root=${native_project_root}/.ohloha
download_cache_root=${ohloha_root}/downloads
source_cache_root=${ohloha_root}/sources
native_cache_root=${ohloha_root}/native
native_sources_root=${native_cache_root}/sources
# ${native_dst_root}/bin will be added to PATH and ${native_dst_root}/lib
# will be added to LD_LIBRARY_PATH when executing build_package
# TODO: move host-python to here
native_dst_root=${native_cache_root}/dst
mkdir -p "${download_cache_root}" "${source_cache_root}" "${native_sources_root}" "${native_dst_root}"


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
get_pkg_legacy_dst_dir() {
    printf '%s.%s' "${TARGET_ROOT}" "${1:-}"
}

get_pkg_dst_dir() {
    local name="${1:-}"
    local work_dst=""

    if [ -n "${target_root_prefix_without_pkgname:-}" ]; then
        work_dst="${target_root_prefix_without_pkgname}.${name}"
        if [ -d "$work_dst" ]; then
            printf '%s' "$work_dst"
            return 0
        fi
    fi

    get_pkg_legacy_dst_dir "$name"
}

get_pkg_install_dir() {
    local name="${1:-}"
    if [ -n "${target_root_prefix_without_pkgname:-}" ]; then
        printf '%s.%s' "${target_root_prefix_without_pkgname}" "$name"
    else
        get_pkg_legacy_dst_dir "$name"
    fi
}

# Move (merge) package $1 from $2 (default ${target_root_prefix_without_pkgname}, output internal directory) to ${target_root_with_pkgname}
mv_pkg_to_dst_dir() {
    local _pkg_name="${1:-}"
    local _pkg_src="${2:-${target_root_prefix_without_pkgname}}"
    local _pkg_dst
    _pkg_dst=$(get_pkg_install_dir "$_pkg_name")
    if [ -d "$_pkg_dst" ]; then
        cp -r ${_pkg_src}/* ${_pkg_dst}/
        rm -rf ${_pkg_src}
    else
        mv ${_pkg_src} ${_pkg_dst}
    fi
}

publish_pkg_to_legacy_dst() {
    local _pkg_name="${1:-${pkg_name:-}}"
    local _pkg_src="${2:-${target_root_with_pkgname:-}}"
    local _pkg_dst

    [ -n "$_pkg_name" ] || { error "publish_pkg_to_legacy_dst: empty package name"; return 1; }
    [ -n "$_pkg_src" ] || { error "publish_pkg_to_legacy_dst: empty source path"; return 1; }
    if [ ! -d "$_pkg_src" ]; then
        error "publish_pkg_to_legacy_dst: source directory not found: '$_pkg_src'"
        return 1
    fi

    _pkg_dst=$(get_pkg_legacy_dst_dir "$_pkg_name")
    if [ "$(readlink -f "$_pkg_src")" = "$(readlink -m "$_pkg_dst")" ]; then
        return 0
    fi

    local _tmp_dst
    _tmp_dst="${_pkg_dst}.tmp.$$"
    rm -rf "$_tmp_dst"
    cp -a "$_pkg_src" "$_tmp_dst"
    rm -rf "$_pkg_dst"
    mv "$_tmp_dst" "$_pkg_dst"
}

# Variable definitions
PKG_VARS=(
    pkg_version pkg_name pkg_deps pkg_build_deps pkg_source_url pkg_release_url
    pkg_license pkg_support_archs pkg_build_type pkg_build_parallism
    pkg_force_clean_build pkg_patch_files
)

AUTOTOOLS_VARS=(
    pkg_build_autotools_extra_configure_flags pkg_build_autotools_bootstrap_script
    pkg_build_autotools_suffix_configure_flags pkg_build_autotools_configure_dir
    pkg_build_autotools_make_install_target
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

set_arch_env_from_cpu() {
    local cpu="${1:-}"
    [ -z "$cpu" ] && return 0
    export OHOS_CPU="$cpu"
    if [ "${OHOS_CPU}" = "aarch64" ]; then
        export OHOS_ARCH="arm64-v8a"
    elif [ "${OHOS_CPU}" = "arm" ]; then
        export OHOS_ARCH="armeabi-v7a"
    elif [ "${OHOS_CPU}" = "x86_64" ]; then
        export OHOS_ARCH="x86_64"
    else
        error "Unsupported cpu '$OHOS_CPU' (supported 'aarch64', 'arm', 'x86_64')"
        return 1
    fi
}

setup_metadata_defaults() {
    export OHOS_SDK="${OHOS_SDK:-}"
    OHOS_SDK_API_VERSION="${OHOS_SDK_API_VERSION:-}"
    if [ -z "${OHOS_CPU:-}" ]; then
        set_arch_env_from_cpu "aarch64"
    elif [ -z "${OHOS_ARCH:-}" ]; then
        set_arch_env_from_cpu "${OHOS_CPU}"
    fi
    export OHOS_LIBDIR="${OHOS_LIBDIR:-lib}"
    TARGET_ROOT="${TARGET_ROOT:-${native_project_root}/dist.${OHOS_CPU}}"
    PATCH_FILE_ROOT="${PATCH_FILE_ROOT:-${native_project_root}/patches}"
    MESON_CROSS_ROOT="${MESON_CROSS_ROOT:-${native_project_root}/meson-scripts}"
    MESON_CROSS_FILE_BASE="${MESON_CROSS_FILE_BASE:-${MESON_CROSS_ROOT}/base.meson}"
    PY_VERSION="${PY_VERSION:-3.12}"
    PY_VERSION_CODE="${PY_VERSION_CODE:-312}"
    BUILD_PLATFORM_TRIPLET="${BUILD_PLATFORM_TRIPLET:-x86_64-pc-linux-gnu}"
    HOST_SYSROOT="${HOST_SYSROOT:-${OHOS_SDK:-}/native/sysroot}"
    HOST_LIBC="${HOST_LIBC:-${HOST_SYSROOT}/usr/lib/${OHOS_CPU}-linux-ohos/libc.so}"
    HOST_PYTHON_DIST="${HOST_PYTHON_DIST:-${TARGET_ROOT}.python3}"
    NUMPY_LIBROOT="${NUMPY_LIBROOT:-}"
    NUMPY2_LIBROOT="${NUMPY2_LIBROOT:-}"
    BUILD_PYTHON="${BUILD_PYTHON:-python3}"
    CC="${CC:-cc}"
    CXX="${CXX:-c++}"
    AS="${AS:-as}"
    LD="${LD:-ld}"
    LDXX="${LDXX:-${LD}}"
    STRIP="${STRIP:-strip}"
    RANLIB="${RANLIB:-ranlib}"
    OBJDUMP="${OBJDUMP:-objdump}"
    OBJCOPY="${OBJCOPY:-objcopy}"
    READELF="${READELF:-readelf}"
    NM="${NM:-nm}"
    AR="${AR:-ar}"
    PROFDATA="${PROFDATA:-profdata}"
    CFLAGS="${CFLAGS:-}"
    CXXFLAGS="${CXXFLAGS:-}"
    CPPFLAGS="${CPPFLAGS:-}"
    LDFLAGS="${LDFLAGS:-}"
    LDSHARED="${LDSHARED:-}"
    PKG_CONFIG_PATH="${PKG_CONFIG_PATH:-}"
    PKG_CONFIG_LIBDIR="${PKG_CONFIG_LIBDIR:-}"
    PKG_CONFIG_SYSTEM_IGNORE_PATH="${PKG_CONFIG_SYSTEM_IGNORE_PATH:-}"
}

json_escape() {
    local value="${1:-}"
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/\\n}
    value=${value//$'\r'/\\r}
    value=${value//$'\t'/\\t}
    printf '%s' "$value"
}

json_string() {
    printf '"%s"' "$(json_escape "${1:-}")"
}

json_csv_array() {
    local csv="${1:-}"
    local first=true item
    printf '['
    if [ -n "$csv" ]; then
        local old_ifs="$IFS"
        IFS=','
        for item in $csv; do
            if [ -z "$item" ]; then
                continue
            fi
            if [ "$first" = true ]; then
                first=false
            else
                printf ','
            fi
            json_string "$item"
        done
        IFS="$old_ifs"
    fi
    printf ']'
}

relpath_from_project() {
    local path="${1:-}"
    local abs_path
    abs_path=$(readlink -f "$path")
    case "$abs_path" in
        "$native_project_root"/*)
            printf '%s' "${abs_path#"$native_project_root"/}"
            ;;
        *)
            printf '%s' "$abs_path"
            ;;
    esac
}

sha256_file() {
    sha256sum "$1" | awk '{print $1}'
}

append_file_hash() {
    local file="${1:-}"
    local out="${2:-}"
    [ -f "$file" ] || return 0
    printf '%s\t%s\n' "$(relpath_from_project "$file")" "$(sha256_file "$file")" >> "$out"
}

normalize_build_input_value() {
    local value="${1:-}"

    if [ -n "${MESON_CROSS_ROOT:-}" ]; then
        value="${value//${MESON_CROSS_ROOT}/__OHLOHA_MESON_CROSS_ROOT__}"
    fi
    if [ -n "${MESON_CROSS_FILE_BASE:-}" ]; then
        value="${value//${MESON_CROSS_FILE_BASE}/__OHLOHA_MESON_CROSS_FILE_BASE__}"
    fi

    printf '%s' "$value"
}

resolve_patch_file() {
    local patch_ref="${1:-}"
    local build_dir="${2:-}"

    if [ -z "$patch_ref" ]; then
        return 1
    elif [[ "$patch_ref" = /* ]]; then
        [ -f "$patch_ref" ] && printf '%s\n' "$patch_ref"
    elif [ -f "${build_dir}/${patch_ref}" ]; then
        printf '%s\n' "${build_dir}/${patch_ref}"
    elif [ -f "${native_project_root}/${patch_ref}" ]; then
        printf '%s\n' "${native_project_root}/${patch_ref}"
    elif [ -f "${PATCH_FILE_ROOT}/${patch_ref}" ]; then
        printf '%s\n' "${PATCH_FILE_ROOT}/${patch_ref}"
    else
        return 1
    fi
}

expand_patch_ref() {
    local patch_ref="${1:-}"
    patch_ref=${patch_ref//\$\{pkg_name\}/${pkg_name:-}}
    patch_ref=${patch_ref//\$pkg_name/${pkg_name:-}}
    patch_ref=${patch_ref//\$\{pkg_version\}/${pkg_version:-}}
    patch_ref=${patch_ref//\$pkg_version/${pkg_version:-}}
    printf '%s' "$patch_ref"
}

detect_referenced_patch_files() {
    local build_file="${1:-}"
    python3 - "$build_file" <<'PY'
import pathlib
import re
import sys

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8", errors="ignore")
patterns = [
    r"\$\{?PATCH_FILE_ROOT\}?/([^\s'\";&|<>]+)",
    r"\$\{?native_project_root\}?/patches/([^\s'\";&|<>]+)",
]
seen = set()
for pattern in patterns:
    for match in re.findall(pattern, text):
        path = "patches/" + match
        if path not in seen:
            seen.add(path)
            print(path)
PY
}

collect_patch_hashes() {
    local build_file="${1:-}"
    local out="${2:-}"
    local build_dir
    build_dir=$(dirname "$(readlink -f "$build_file")")

    local patch_ref patch_file
    if [ -n "${pkg_patch_files:-}" ]; then
        local old_ifs="$IFS"
        IFS=','
        for patch_ref in $pkg_patch_files; do
            patch_ref=$(expand_patch_ref "$patch_ref")
            [ -z "$patch_ref" ] && continue
            if ! patch_file=$(resolve_patch_file "$patch_ref" "$build_dir"); then
                error "declared patch file not found: $patch_ref"
                return 1
            fi
            append_file_hash "$patch_file" "$out"
        done
        IFS="$old_ifs"
    fi

    while IFS= read -r patch_ref; do
        patch_ref=$(expand_patch_ref "$patch_ref")
        [ -z "$patch_ref" ] && continue
        if patch_file=$(resolve_patch_file "$patch_ref" "$build_dir"); then
            append_file_hash "$patch_file" "$out"
        fi
    done < <(detect_referenced_patch_files "$build_file")
}

source_archive_path_for_url() {
    local url="${1:-}"
    local source_digest
    source_digest=$(printf '%s' "$url" | sha256sum | awk '{print $1}')
    printf '%s/sha256-%s.archive' "$download_cache_root" "$source_digest"
}

compute_patched_source_snapshot_dir() {
    local build_file="${1:-}"
    local id_input patch_hashes source_archive source_identity
    id_input=$(mktemp)
    patch_hashes=$(mktemp)
    cleanup_patched_snapshot_tmp() {
        rm -f "$id_input" "$patch_hashes"
    }

    source_identity="source-url:${current_source_url:-}"
    if [ -n "${current_source_url:-}" ]; then
        source_archive=$(source_archive_path_for_url "$current_source_url")
        if [ -f "$source_archive" ]; then
            source_identity="source-archive:sha256:$(sha256_file "$source_archive")"
        fi
    fi

    append_file_hash "$build_file" "$patch_hashes"
    local build_dir postinst_name
    build_dir=$(dirname "$(readlink -f "$build_file")")
    for postinst_name in postinst POSTINST PostInst; do
        append_file_hash "${build_dir}/${postinst_name}" "$patch_hashes"
    done
    collect_patch_hashes "$build_file" "$patch_hashes" || { cleanup_patched_snapshot_tmp; return 1; }

    {
        printf 'format=1\n'
        printf 'pkg_name=%s\n' "${pkg_name:-}"
        printf 'pkg_version=%s\n' "${pkg_version:-}"
        printf 'source_identity=%s\n' "$source_identity"
        printf 'ohos_cpu=%s\n' "${OHOS_CPU:-}"
        printf 'ohos_arch=%s\n' "${OHOS_ARCH:-}"
        sort -u "$patch_hashes"
    } > "$id_input"

    local patched_digest patched_dir
    patched_digest=$(sha256_file "$id_input")
    patched_dir="${source_cache_root}/sha256-${patched_digest}/patched"
    cleanup_patched_snapshot_tmp
    printf '%s\n' "$patched_dir"
}

publish_patched_source_snapshot() {
    local build_file="${1:-}"
    local source_root="${2:-}"
    [ -d "$source_root" ] || return 0

    local patched_dir patched_id
    patched_dir=$(compute_patched_source_snapshot_dir "$build_file") || return 1
    patched_id=$(basename "$(dirname "$patched_dir")")

    publish_patched_source_snapshot_unlocked() {
        local _source_root="${1:?source root must be set}"
        local _patched_dir="${2:?patched dir must be set}"
        [ -d "$_patched_dir" ] && return 0

        mkdir -p "$(dirname "$_patched_dir")"
        local _tmp_patched
        _tmp_patched=$(mktemp -d "${_patched_dir}.tmp.XXXXXX") || return 1
        rm -rf "$_tmp_patched"
        if ! cp -a "$_source_root" "$_tmp_patched"; then
            rm -rf "$_tmp_patched"
            return 1
        fi
        if ! mv "$_tmp_patched" "$_patched_dir"; then
            rm -rf "$_tmp_patched"
            return 1
        fi
    }

    if declare -F with_ohloha_lock >/dev/null 2>&1; then
        if ! with_ohloha_lock "patched-source-${patched_id}" publish_patched_source_snapshot_unlocked "$source_root" "$patched_dir"; then
            return 1
        fi
    else
        if ! publish_patched_source_snapshot_unlocked "$source_root" "$patched_dir"; then
            return 1
        fi
    fi
}

prepare_work_source_root() {
    local build_file="${1:-}"
    local fallback_source_root="${2:-}"
    local source_root="$fallback_source_root"
    local patched_dir

    if patched_dir=$(compute_patched_source_snapshot_dir "$build_file") && [ -d "$patched_dir" ]; then
        source_root="$patched_dir"
    fi

    if [ ! -d "$source_root" ]; then
        error "cannot prepare work source; source directory not found: '$source_root'"
        return 1
    fi
    if [ -z "${current_work_root:-}" ]; then
        return 0
    fi

    local work_sources_root work_source_root
    work_sources_root="${current_work_root}/src-root"
    work_source_root="${work_sources_root}/${pkg_name}"
    rm -rf "$work_source_root"
    mkdir -p "$work_sources_root"
    if ! cp -a "$source_root" "$work_source_root"; then
        error "failed to copy source into workdir: '$source_root' -> '$work_source_root'"
        return 1
    fi

    sources_root="$work_sources_root"
    current_source_root="$work_source_root"
}

compute_build_work_root() {
    local build_file="${1:-}"
    local id_input patch_hashes source_archive source_archive_sha256
    id_input=$(mktemp)
    patch_hashes=$(mktemp)
    cleanup_build_work_tmp() {
        rm -f "$id_input" "$patch_hashes"
    }

    source_archive_sha256=""
    if [ -n "${pkg_source_url:-}" ]; then
        source_archive=$(source_archive_path_for_url "$pkg_source_url")
        if [ -f "$source_archive" ]; then
            source_archive_sha256="sha256:$(sha256_file "$source_archive")"
        fi
    fi

    append_file_hash "$build_file" "$patch_hashes"
    collect_patch_hashes "$build_file" "$patch_hashes" || { cleanup_build_work_tmp; return 1; }

    {
        printf 'format=1\n'
        printf 'pkg_name=%s\n' "${pkg_name:-}"
        printf 'pkg_version=%s\n' "${pkg_version:-}"
        printf 'pkg_build_type=%s\n' "${pkg_build_type:-}"
        printf 'ohos_cpu=%s\n' "${OHOS_CPU:-}"
        printf 'ohos_arch=%s\n' "${OHOS_ARCH:-}"
        printf 'ohos_api=%s\n' "${OHOS_SDK_API_VERSION:-}"
        printf 'source_archive_sha256=%s\n' "$source_archive_sha256"
        printf 'cflags=%s\n' "${CFLAGS:-}"
        printf 'cxxflags=%s\n' "${CXXFLAGS:-}"
        printf 'cppflags=%s\n' "${CPPFLAGS:-}"
        printf 'ldflags=%s\n' "${LDFLAGS:-}"
        printf 'pkg_config_libdir=%s\n' "${PKG_CONFIG_LIBDIR:-}"
        local var
        for var in "${PKG_VARS[@]}" "${AUTOTOOLS_VARS[@]}" "${CMAKE_VARS[@]}" "${MESON_VARS[@]}"; do
            printf 'var:%s=%s\n' "$var" "$(normalize_build_input_value "${!var:-}")"
        done
        sort -u "$patch_hashes" | sed 's/^/file:/'
    } > "$id_input"

    local digest
    digest=$(sha256_file "$id_input")
    printf '%s/work/sha256-%s' "$ohloha_root" "$digest"
    cleanup_build_work_tmp
}

prepare_meson_cross_file_for_build() {
    local cross_file="${1:-${MESON_CROSS_FILE_BASE:-}}"
    if [ -z "$cross_file" ] || [ -z "${current_work_root:-}" ]; then
        printf '%s' "$cross_file"
        return 0
    fi
    if [ ! -f "$cross_file" ]; then
        printf '%s' "$cross_file"
        return 0
    fi

    local meson_dir dst
    meson_dir="${current_work_root}/meson"
    mkdir -p "$meson_dir"
    dst="${meson_dir}/$(basename "$cross_file")"
    if [ "$(readlink -f "$cross_file")" != "$(readlink -m "$dst")" ]; then
        cp "$cross_file" "$dst"
    fi
    printf '%s' "$dst"
}

get_pkg_patch_files() {
    local build_dir="${current:-${native_project_root}}"
    local patch_refs=("$@")
    local patch_ref patch_file

    if [ "${#patch_refs[@]}" -eq 0 ]; then
        if [ -z "${pkg_patch_files:-}" ]; then
            return 0
        fi
        local old_ifs="$IFS"
        IFS=','
        read -r -a patch_refs <<< "${pkg_patch_files}"
        IFS="$old_ifs"
    fi

    for patch_ref in "${patch_refs[@]}"; do
        patch_ref=$(expand_patch_ref "$patch_ref")
        [ -z "$patch_ref" ] && continue
        if ! patch_file=$(resolve_patch_file "$patch_ref" "$build_dir"); then
            error "patch file not found: $patch_ref"
            return 1
        fi
        printf '%s\n' "$patch_file"
    done
}

apply_pkg_patches() {
    local strip_level="-p1"
    if [[ "${1:-}" =~ ^-p[0-9]+$ ]]; then
        strip_level="$1"
        shift
    fi

    local patch_list patch_file
    patch_list=$(get_pkg_patch_files "$@") || return 1
    while IFS= read -r patch_file; do
        [ -z "$patch_file" ] && continue
        patch "$strip_level" --dry-run < "$patch_file"
        patch "$strip_level" < "$patch_file"
    done <<< "$patch_list"
}

apply_pkg_git_patches() {
    local src_root="${current_source_root:-}"
    if [ -z "$src_root" ]; then
        error "current_source_root is empty; apply_pkg_git_patches must run inside a package build hook"
        return 1
    fi

    local patch_list patch_file
    patch_list=$(get_pkg_patch_files "$@") || return 1
    while IFS= read -r patch_file; do
        [ -z "$patch_file" ] && continue
        git -C "$src_root" apply --check "$patch_file"
        git -C "$src_root" apply "$patch_file"
    done <<< "$patch_list"
}

json_file_hash_object() {
    local file="${1:-}"
    local first=true rel hash
    printf '{'
    while IFS=$'\t' read -r rel hash; do
        [ -z "$rel" ] && continue
        if [ "$first" = true ]; then
            first=false
        else
            printf ','
        fi
        printf '\n    '; json_string "$rel"; printf ': '; json_string "sha256:$hash"
    done < <(sort -u "$file")
    if [ "$first" = false ]; then
        printf '\n  '
    fi
    printf '}'
}

print_package_meta() {
    local build_file="${1:-}"
    [[ ! -f "$build_file" ]] && error "BUILD file not found: $build_file" && return 1

    clear_vars
    setup_metadata_defaults || { clear_vars; return 1; }
    source "$build_file"
    setup || { error "setup() failed"; clear_vars; return 1; }
    validate_config || { clear_vars; return 1; }

    local abs_build_file
    abs_build_file=$(readlink -f "$build_file")
    local rel_build_file="$abs_build_file"
    case "$abs_build_file" in
        "$native_project_root"/*)
            rel_build_file="${abs_build_file#"$native_project_root"/}"
            ;;
    esac

    printf '{\n'
    printf '  "name": '; json_string "${pkg_name:-}"; printf ',\n'
    printf '  "version": '; json_string "${pkg_version:-}"; printf ',\n'
    printf '  "build_file": '; json_string "$rel_build_file"; printf ',\n'
    printf '  "deps": '; json_csv_array "${pkg_deps:-}"; printf ',\n'
    printf '  "build_deps": '; json_csv_array "${pkg_build_deps:-}"; printf ',\n'
    printf '  "source_url": '; json_string "${pkg_source_url:-}"; printf ',\n'
    printf '  "release_url": '; json_string "${pkg_release_url:-}"; printf ',\n'
    printf '  "license": '; json_string "${pkg_license:-}"; printf ',\n'
    printf '  "support_archs": '; json_csv_array "${pkg_support_archs:-}"; printf ',\n'
    printf '  "build_type": '; json_string "${pkg_build_type:-}"; printf ',\n'
    printf '  "patch_files": '; json_csv_array "${pkg_patch_files:-}"; printf '\n'
    printf '}\n'

    clear_vars
}

load_sdk_api_version_for_metadata() {
    if [ -n "${OHOS_SDK_API_VERSION:-}" ]; then
        return 0
    fi
    if [ -n "${OHOS_SDK:-}" ] && [ -f "${OHOS_SDK}/toolchains/oh-uni-package.json" ]; then
        OHOS_SDK_API_VERSION=$(python3 - "$OHOS_SDK/toolchains/oh-uni-package.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    print(json.load(f).get("apiVersion", ""))
PY
)
    fi
}

tool_version_line() {
    local tool="${1:-}"
    if [ -z "$tool" ]; then
        return 0
    fi
    if [ -x "$tool" ]; then
        "$tool" --version 2>/dev/null | sed -n '1p' || true
    elif command -v "$tool" >/dev/null 2>&1; then
        "$tool" --version 2>/dev/null | sed -n '1p' || true
    fi
}

print_package_cache_key() {
    local build_file="${1:-}"
    [[ ! -f "$build_file" ]] && error "BUILD file not found: $build_file" && return 1

    clear_vars
    setup_metadata_defaults || { clear_vars; return 1; }
    load_sdk_api_version_for_metadata
    source "$build_file"
    setup || { error "setup() failed"; clear_vars; return 1; }
    validate_config || { clear_vars; return 1; }

    local abs_build_file rel_build_file build_dir source_archive source_archive_sha256
    abs_build_file=$(readlink -f "$build_file")
    rel_build_file=$(relpath_from_project "$abs_build_file")
    build_dir=$(dirname "$abs_build_file")
    source_archive_sha256=""
    if [ -n "${pkg_source_url:-}" ]; then
        source_archive=$(source_archive_path_for_url "$pkg_source_url")
        if [ -f "$source_archive" ]; then
            source_archive_sha256="sha256:$(sha256_file "$source_archive")"
        fi
    fi

    local file_hashes input_blob
    file_hashes=$(mktemp)
    input_blob=$(mktemp)
    cleanup_cache_key_tmp() {
        rm -f "$file_hashes" "$input_blob"
    }

    append_file_hash "$abs_build_file" "$file_hashes"
    for postinst_name in postinst POSTINST PostInst; do
        append_file_hash "${build_dir}/${postinst_name}" "$file_hashes"
    done
    append_file_hash "${native_project_root}/builder.sh" "$file_hashes"
    append_file_hash "${native_project_root}/setup2.sh" "$file_hashes"
    append_file_hash "${native_project_root}/cleanup.sh" "$file_hashes"
    append_file_hash "${native_project_root}/cmake/ohos.toolchain.xhw.cmake" "$file_hashes"
    for meson_template in "${native_project_root}"/meson-scripts/*.meson.template; do
        [ -f "$meson_template" ] && append_file_hash "$meson_template" "$file_hashes"
    done
    if ! collect_patch_hashes "$abs_build_file" "$file_hashes"; then
        cleanup_cache_key_tmp
        clear_vars
        return 1
    fi

    {
        printf 'format=1\n'
        printf 'name=%s\n' "${pkg_name:-}"
        printf 'version=%s\n' "${pkg_version:-}"
        printf 'build_file=%s\n' "$rel_build_file"
        printf 'ohos_cpu=%s\n' "${OHOS_CPU:-}"
        printf 'ohos_arch=%s\n' "${OHOS_ARCH:-}"
        printf 'ohos_sdk=%s\n' "${OHOS_SDK:-}"
        printf 'ohos_api=%s\n' "${OHOS_SDK_API_VERSION:-}"
        printf 'ohos_libdir=%s\n' "${OHOS_LIBDIR:-}"
        printf 'target_root=%s\n' "${TARGET_ROOT:-}"
        printf 'host_sysroot=%s\n' "${HOST_SYSROOT:-}"
        printf 'source_archive_sha256=%s\n' "$source_archive_sha256"
        printf 'clang=%s\n' "$(tool_version_line "${OHOS_SDK:-}/native/llvm/bin/clang")"
        printf 'cmake=%s\n' "$(tool_version_line cmake)"
        printf 'meson=%s\n' "$(tool_version_line meson)"
        printf 'ninja=%s\n' "$(tool_version_line ninja)"
        printf 'python=%s\n' "$(tool_version_line python3)"
        local var
        for var in "${PKG_VARS[@]}" "${AUTOTOOLS_VARS[@]}" "${CMAKE_VARS[@]}" "${MESON_VARS[@]}"; do
            printf 'var:%s=%s\n' "$var" "$(normalize_build_input_value "${!var:-}")"
        done
        sort -u "$file_hashes" | sed 's/^/file:/'
    } > "$input_blob"

    local digest
    digest=$(sha256_file "$input_blob")

    printf '{\n'
    printf '  "format": 1,\n'
    printf '  "algorithm": "sha256",\n'
    printf '  "build_id": '; json_string "sha256:$digest"; printf ',\n'
    printf '  "name": '; json_string "${pkg_name:-}"; printf ',\n'
    printf '  "version": '; json_string "${pkg_version:-}"; printf ',\n'
    printf '  "build_file": '; json_string "$rel_build_file"; printf ',\n'
    printf '  "arch": '; json_string "${OHOS_CPU:-}"; printf ',\n'
    printf '  "ohos_api": '; json_string "${OHOS_SDK_API_VERSION:-}"; printf ',\n'
    printf '  "source_archive_sha256": '; json_string "$source_archive_sha256"; printf ',\n'
    printf '  "deps": '; json_csv_array "${pkg_deps:-}"; printf ',\n'
    printf '  "build_deps": '; json_csv_array "${pkg_build_deps:-}"; printf ',\n'
    printf '  "patch_files": '; json_csv_array "${pkg_patch_files:-}"; printf ',\n'
    printf '  "files": '; json_file_hash_object "$file_hashes"; printf '\n'
    printf '}\n'

    cleanup_cache_key_tmp
    clear_vars
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
    _presetup_destdir=${DESTDIR:-}
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
    DESTDIR=$_presetup_destdir
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
    [[ -n "${pkg_patch_files:-}" ]] && ! validate_no_space "$pkg_patch_files" && error "pkg_patch_files cannot contain spaces" && ((errors++))

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

    local source_digest archive_path
    source_digest=$(printf '%s' "$url" | sha256sum | awk '{print $1}')
    archive_path="${download_cache_root}/sha256-${source_digest}.archive"

    download_source_archive() {
        local _url="${1:?download url must be set}"
        local _archive_path="${2:?archive path must be set}"
        [ -f "$_archive_path" ] && return 0

        mkdir -p "$(dirname "$_archive_path")"
        local _tmp_archive
        _tmp_archive=$(mktemp "${_archive_path}.tmp.XXXXXX") || return 1
        if ! wget -O "$_tmp_archive" -- "$_url"; then
            rm -f "$_tmp_archive"
            return 1
        fi
        mv "$_tmp_archive" "$_archive_path"
    }

    extract_clean_source_snapshot() {
        local _archive_path="${1:?archive path must be set}"
        local _clean_dir="${2:?clean source dir must be set}"
        [ -d "$_clean_dir" ] && return 0

        local _tmpd _tmp_clean
        _tmpd=$(mktemp -d) || return 1
        mkdir -p "$(dirname "$_clean_dir")"
        _tmp_clean=$(mktemp -d "${_clean_dir}.tmp.XXXXXX") || { rm -rf "$_tmpd"; return 1; }

        _cleanup_extract() {
            rm -rf -- "$_tmpd" "$_tmp_clean"
        }

        local _mime
        _mime=$(file -b --mime-type "$_archive_path" 2>/dev/null || echo "")

        case "$_mime" in
            application/zip)
                if ! unzip -q "$_archive_path" -d "$_tmpd"; then error "wget_source unzip failed"; _cleanup_extract; return 1; fi
                ;;
            application/x-xz|application/x-7z-compressed)
                if ! tar -xJf "$_archive_path" -C "$_tmpd"; then error "wget_source tar -J failed"; _cleanup_extract; return 1; fi
                ;;
            application/gzip|application/x-gzip)
                if ! tar -xzf "$_archive_path" -C "$_tmpd"; then error "wget_source tar -z failed"; _cleanup_extract; return 1; fi
                ;;
            application/x-tar)
                if ! tar -xf "$_archive_path" -C "$_tmpd"; then error "wget_source tar failed"; _cleanup_extract; return 1; fi
                ;;
            *)
                # fallback: try tar then unzip
                if tar -tf "$_archive_path" >/dev/null 2>&1; then
                    if ! tar -xf "$_archive_path" -C "$_tmpd"; then error "wget_source tar fallback failed"; _cleanup_extract; return 1; fi
                elif unzip -t "$_archive_path" >/dev/null 2>&1; then
                    if ! unzip -q "$_archive_path" -d "$_tmpd"; then error "wget_source unzip fallback failed"; _cleanup_extract; return 1; fi
                else
                    error "wget_source unknown or unsupported archive format: '$_mime'"
                    _cleanup_extract
                    return 1
                fi
                ;;
        esac

        # list top-level entries (one-per-line). Note: this will break only for entries with embedded newlines.
        local _top_entries _count _topdir
        _top_entries=$(find "$_tmpd" -mindepth 1 -maxdepth 1 -print)
        _count=$(printf '%s\n' "$_top_entries" | sed -n '$=')

        if [ "$_count" -ne 1 ]; then
            error "wget_source archive must contain exactly one top-level entry (found $_count)"
            _cleanup_extract
            return 1
        fi

        _topdir=$(printf '%s\n' "$_top_entries" | sed -n '1p')

        if [ ! -d "$_topdir" ]; then
            error "wget_source top-level entry is not a directory"
            _cleanup_extract
            return 1
        fi

        rm -rf "$_tmp_clean"
        if ! mv -- "$_topdir" "$_tmp_clean"; then
            error "wget_source clean snapshot move failed"
            _cleanup_extract
            return 1
        fi
        if ! mv "$_tmp_clean" "$_clean_dir"; then
            error "wget_source clean snapshot publish failed"
            _cleanup_extract
            return 1
        fi
        _cleanup_extract
    }

    # download archive once, then extract from the local cache
    if declare -F with_ohloha_lock >/dev/null 2>&1; then
        if ! with_ohloha_lock "download-${source_digest}" download_source_archive "$url" "$archive_path"; then
            error "wget_source download failed"
            return 1
        fi
    elif ! download_source_archive "$url" "$archive_path"; then
        error "wget_source download failed"
        return 1
    fi

    local archive_digest clean_dir
    archive_digest=$(sha256_file "$archive_path")
    clean_dir="${source_cache_root}/sha256-${archive_digest}/clean"

    if declare -F with_ohloha_lock >/dev/null 2>&1; then
        if ! with_ohloha_lock "source-sha256-${archive_digest}" extract_clean_source_snapshot "$archive_path" "$clean_dir"; then
            error "wget_source clean source snapshot failed"
            return 1
        fi
    elif ! extract_clean_source_snapshot "$archive_path" "$clean_dir"; then
        error "wget_source clean source snapshot failed"
        return 1
    fi

    # copy clean source snapshot to desired output location
    if [ -d "${output_dir}" ]; then
        rm -rf "${output_dir}"
    fi
    mkdir -p "$(dirname "${output_dir}")"
    if ! cp -a "$clean_dir" "${output_dir}"; then
        error "wget_source clean source copy failed"
        return 1
    fi

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

    # Set up Rust/PyO3/cc-rs/ASM cross-compilation env vars centrally.
    # Individual BUILD files no longer need to set these.
    setup_rust_cross_compile
}

destroy_pycrossenv() {
    exit_pycrossenv
}

download() {
    local max_retries=3
    local retry_delay=15
    local attempt=1
    
    _custom_download_source_continue=true
    custom_download_source || { warn "custom_download_source process for '$current_source_root' failed"; return 1; }
    if [ "x$_custom_download_source_continue" != "xtrue" ]; then
        current_source_fresh=true
        return 0
    fi
    
    while [ $attempt -le $max_retries ]; do
        if wget_source "${current_source_url}" "${current_source_root}"; then
            # source downloaded to ${current_source_root}
            current_source_fresh=true
            return 0
        fi
        
        if [ $attempt -lt $max_retries ]; then
            warn "Download attempt $attempt failed. Retrying in ${retry_delay} seconds..."
            sleep $retry_delay
            attempt=$((attempt + 1))
        else
            warn "Download failed after $max_retries attempts"
            return 1
        fi
    done
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
    local build_sources_root="${SRC_ROOT}"
    if [ -n "${current_source_root:-}" ]; then
        target=$(basename "$current_source_root")
        build_sources_root=$(dirname "$current_source_root")
    fi
    # parse build deps
    local deps_sep_space=$(get_pkg_names_from_deps "$pkg_build_deps")
    local cmake_build_dir="ohos-build"
    local meson_build_dir="ohos-build"
    local meson_cross_file="${pkg_build_meson_cross_file:-}"
    if [ -n "${current_work_root:-}" ]; then
        cmake_build_dir="${current_work_root}/build/cmake"
        meson_build_dir="${current_work_root}/build/meson"
    fi
    meson_cross_file=$(prepare_meson_cross_file_for_build "$meson_cross_file")

    info "start building '$pkg_name' with deps: '$deps_sep_space'"

    # custom build process hook in BUILD
    _custom_build_continue=true
    custom_build || { warn "custom_build process for '$pkg_name' failed"; return 1; }
    if [ "x$_custom_build_continue" != "xtrue" ]; then
        info "skipping normal build process"
        return 0;
    fi

    pushd "$build_sources_root"

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
                "$pkg_build_autotools_make_install_target" \
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
                "$cmake_build_dir" \
            || { error "build_cmakeproj_with_deps failed"; return 1; }
            ;;
        xmeson)
            build_mesonproj_with_deps \
                "$target" \
                "$deps_sep_space" \
                "$meson_cross_file" \
                "$pkg_build_meson_extra_meson_flags" \
                "$pkg_build_parallism" \
                "$pkg_build_meson_extra_cflags" \
                "$pkg_build_meson_extra_ldflags" \
                "$pkg_build_meson_extra_cmake_prefix_path" \
                "$pkg_build_meson_extra_cmake_findroot_path" \
                "$meson_build_dir" \
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

    # setup dependencies for native binaries & libraries
    PATH="${native_dst_root}/bin:$PATH"
    LD_LIBRARY_PATH="${native_dst_root}/lib:$LD_LIBRARY_PATH"
    
    post_configure_hook() { :; }

    source "$build_file"
    setup || { error "setup() failed"; restore_xcompile_flags; clear_vars; return 1; }
    validate_config || { restore_xcompile_flags; clear_vars; return 1; }
    
    # setup local variables for hooks
    current_source_url="$pkg_source_url"
    current="$(dirname $(readlink -f $build_file))"
    sources_root="${SRC_ROOT}"
    current_source_root="${SRC_ROOT}/${pkg_name}"
    current_build_root=""
    target_root_prefix_without_pkgname=""
    target_root_with_pkgname=""
    current_source_fresh=false
    current_work_root=$(compute_build_work_root "$build_file") || {
        error "compute_build_work_root for '$build_file' failed"
        restore_xcompile_flags
        clear_vars
        return 1
    }
    mkdir -p "$current_work_root"
    target_root_prefix_without_pkgname="${current_work_root}/install/dist.${OHOS_CPU}"
    target_root_with_pkgname="$(get_pkg_install_dir "$pkg_name")"
    rm -rf "${target_root_prefix_without_pkgname}" "${target_root_with_pkgname}"

    # download if ${current_source_root} doesn't exist or flushed using optional pkg_force_clean_build
    if [ -n "${pkg_force_clean_build:-}" ]; then
        rm -rf "${current_source_root}"
    fi
    if [ ! -d "${current_source_root}" ]; then
        download || { error "download for '$build_file' failed"; restore_xcompile_flags; clear_vars; return 1; }
    fi

    local legacy_source_root="$current_source_root"
    print_vars
    if [ ! -f "${current_source_root}/PATCHED_BY_OHLOHA" ]; then
        prebuilt_patch_once_hook || { error "prebuilt_patch_once_hook for '$build_file' failed"; restore_xcompile_flags; clear_vars; return 1; }
        touch "${current_source_root}/PATCHED_BY_OHLOHA"
    fi
    if [ "x${current_source_fresh:-false}" = "xtrue" ]; then
        publish_patched_source_snapshot "$build_file" "$current_source_root" || {
            error "publish_patched_source_snapshot for '$build_file' failed"
            restore_xcompile_flags
            clear_vars
            return 1
        }
    fi
    prepare_work_source_root "$build_file" "$legacy_source_root" || {
        error "prepare_work_source_root for '$build_file' failed"
        restore_xcompile_flags
        clear_vars
        return 1
    }
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

    publish_pkg_to_legacy_dst "$pkg_name" "$target_root_with_pkgname" || {
        error "publish_pkg_to_legacy_dst for '$build_file' failed"
        restore_xcompile_flags
        clear_vars
        return 1
    }

    restore_xcompile_flags
    clear_vars
    info "Build $build_file completed"
    return 0
}

# NOTE: we will not resolve dependencies here! Make sure BUILD_FILEs are already topologically sorted
main() {
    local CONTINUE_ON_FAIL=false
    local OHOS_CPU_VALUE=""
    local PRINT_META=false
    local BUILD_ONE=false
    local CACHE_KEY=false

    # parse simple options
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --print-meta)
                PRINT_META=true
                shift
                ;;
            --cache-key)
                CACHE_KEY=true
                shift
                ;;
            --build-one)
                BUILD_ONE=true
                shift
                ;;
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

    [[ $# -eq 0 ]] && echo "Usage: $0 [--print-meta] [--cache-key] [--build-one] [--continue-on-fail] [--cpu=aarch64|arm|x86_64] <BUILD_FILE> [BUILD_FILE...]" && exit 1

    if [ "$PRINT_META" = true ]; then
        if [ "$#" -ne 1 ]; then
            error "--print-meta expects exactly one BUILD file"
            exit 2
        fi
        if [ -n "$OHOS_CPU_VALUE" ]; then
            set_arch_env_from_cpu "$OHOS_CPU_VALUE" || exit 1
        fi
        print_package_meta "$1"
        exit $?
    fi

    if [ "$CACHE_KEY" = true ]; then
        if [ "$#" -ne 1 ]; then
            error "--cache-key expects exactly one BUILD file"
            exit 2
        fi
        if [ -n "$OHOS_CPU_VALUE" ]; then
            set_arch_env_from_cpu "$OHOS_CPU_VALUE" || exit 1
        fi
        print_package_cache_key "$1"
        exit $?
    fi

    if [ "$BUILD_ONE" = true ] && [ "$#" -ne 1 ]; then
        error "--build-one expects exactly one BUILD file"
        exit 2
    fi

    # trigger presetup env hooks
    for build_file in "$@"; do
        LOAD_NATIVE_HOOK_ONLY=true source "$build_file"
        native_env_hook || { echo "fatal: native_env_hook failed"; exit 1; }
    done

    # Specify OHOS_CPU & OHOS_ARCH for setup.sh if --cpu was provided
    if [ -n "$OHOS_CPU_VALUE" ]; then
        set_arch_env_from_cpu "$OHOS_CPU_VALUE" || exit 1
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
