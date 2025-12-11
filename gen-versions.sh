#!/bin/sh
# collect_versions.sh
# Read each subdirectory in the script directory (no recursion).
# For each subdir that contains a "BUILD" file, extract:
#   pkg_name, pkg_version, pkg_deps, pkg_build_deps
# and append a line to VERSION:
#   <pkg_name> <pkg_version> <pkg_deps> <pkg_build_deps>
# Fields are expected to be like: pkg_name="xxx" (no spaces inside values).

set -eu

# directory where this script is located
SCRIPT_DIR=$(dirname $(readlink -f $0))
cd ${SCRIPT_DIR}

VERSION_FILE="$SCRIPT_DIR/VERSION"
rm -f $VERSION_FILE

# helper: extract value of a key from a file (removes surrounding double quotes)
# usage: extract KEY FILE
extract() {
  key=$1
  file=$2
  # safe sed: match lines that start with key= and capture value inside quotes (or value without quotes)
  # returns first match or empty string
  sed -n "s/^${key}=\(.*\)/\1/p" "$file" | sed -n '1p' | {
    read val || true
    if [ -n "${val:-}" ]; then
      # remove optional surrounding quotes (only double quotes expected per spec)
      # also remove trailing/leading spaces (defensive)
      # POSIX parameter expansion for trimming is not standard, so use sed
      printf '%s' "$val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//'
    fi
  }
}

# Iterate subdirectories only (non-recursive)
for entry in "$SCRIPT_DIR"/*; do
  [ -d "$entry" ] || continue   # skip non-directories
  BUILD_FILE="$entry/BUILD"
  [ -f "$BUILD_FILE" ] || continue  # skip if no BUILD file

  # Extract fields (may be empty if not present)
  pkg_name=$(extract 'pkg_name' "$BUILD_FILE" || true)
  pkg_version=$(extract 'pkg_version' "$BUILD_FILE" || true)
  pkg_deps=$(extract 'pkg_deps' "$BUILD_FILE" || true)
  pkg_build_deps=$(extract 'pkg_build_deps' "$BUILD_FILE" || true)

  # Ensure values have no embedded newlines or spaces according to guarantee.
  # Replace any newline characters defensively (shouldn't happen).
  pkg_name=$(printf '%s' "$pkg_name" | tr '\n' ' ')
  pkg_version=$(printf '%s' "$pkg_version" | tr '\n' ' ')
  pkg_deps=$(printf '%s' "$pkg_deps" | tr '\n' ' ')
  pkg_build_deps=$(printf '%s' "$pkg_build_deps" | tr '\n' ' ')

  # Append to VERSION with tab separators
  printf '%s\t%s\t%s\t%s\n' "$pkg_name" "$pkg_version" "$pkg_deps" "$pkg_build_deps" >> "$VERSION_FILE"
done

