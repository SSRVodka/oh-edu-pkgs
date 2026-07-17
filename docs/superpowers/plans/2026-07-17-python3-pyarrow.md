# Python3 PyArrow 18.0.0 Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a locally verified OpenHarmony cross-build for `python3-pyarrow` 18.0.0 against the trimmed `arrow-cpp` 18.0.0 package.

**Architecture:** Build the official PyPI sdist through the repository's Python crossenv and PyArrow's setuptools/CMake backend. A package-private patch makes CSV, JSON, and filesystem extensions follow the Arrow feature configuration and lets the build consume resolved target NumPy headers without importing a host NumPy. Arrow shared libraries are copied into the wheel by PyArrow's supported bundle option.

**Tech Stack:** Bash package hooks, crossenv, PEP 517/setuptools, Cython, CMake, Apache Arrow C++, NumPy, OHOS Clang toolchain.

## Global Constraints

- Target exactly `python3-pyarrow` 18.0.0 and `arrow-cpp==18.0.0`.
- Do not modify `arrow-cpp/`.
- Enable CSV.
- Disable JSON, filesystem, Parquet, Dataset, Acero, ORC, Gandiva, Plasma, and Flight.
- Set `PYARROW_BUNDLE_ARROW_CPP=1` so Arrow shared libraries are bundled in the wheel.
- Do not install NumPy through `${PYCROSS_BUILD_PIP}`; use headers from the resolved target `python3-numpy>=1.25` package.
- Preserve `--no-deps`, `--no-build-isolation`, and `--no-binary :all:` for the source wheel build.
- Keep `setup()` metadata-only and use only versioned dependency paths returned by `get_pkg_dst_dir`.
- Do not run an aarch64 build on `kiwi`; verification is local.
- Do not add `.ohloha/`, `dist*`, wheel output, staging output, or unrelated user files to a commit.

---

## File Structure

- `python3-pyarrow/BUILD`: package metadata, dependency declarations, crossenv lifecycle, target NumPy and Arrow resolution, PyArrow feature environment, and wheel installation.
- `python3-pyarrow/POSTINST`: retain the generated no-op strict-mode post-install hook.
- `python3-pyarrow/patches/18.0.0/ohos-feature-selection-and-target-numpy.patch`: upstream adaptation for explicit target NumPy headers and conditional CSV/JSON/filesystem extensions.
- `PKG_INDEX.json`: generated package metadata entry for `python3-pyarrow`.

### Task 1: Define the Package and Cross-Build Hook

**Files:**
- Modify: `python3-pyarrow/BUILD`
- Verify unchanged: `python3-pyarrow/POSTINST`

**Interfaces:**
- Consumes: `setup_pycrossenv`, `destroy_pycrossenv`, `get_pkg_dst_dir`, `build_python_cross_package_active`, `install_current_python_wheelhouse_to_target_site_packages`, `CMAKE_TOOLCHAIN_CONFIG`, `HOST_PYTHON_DIST`, `PYCROSS_CROSS_PYTHON`, `PYCROSS_BUILD_PIP`, `OHOS_ARCH`, `OHOS_LIBDIR`, and `PY_VERSION` from the repository build system.
- Produces: package metadata named `python3-pyarrow` version `18.0.0`; a wheelhouse populated by `build_python_cross_package_active`; build environment variable `PYARROW_NUMPY_INCLUDE_DIR` consumed by the package patch in Task 2.

- [ ] **Step 1: Run the metadata check and verify the scaffold fails for the expected reason**

Run:

```bash
OHOS_SDK=/tools/ohos-sdk/18 OHOS_CPU=x86_64 \
  ./builder.sh --print-meta python3-pyarrow/BUILD
```

Expected: nonzero exit with `pkg_version is required` and/or `pkg_build_type is required`, proving the empty scaffold is not a valid package.

- [ ] **Step 2: Replace `python3-pyarrow/BUILD` with the complete package implementation**

Use this exact content:

```bash
#!/bin/bash
set -Eeuo pipefail

setup() {

pkg_version="18.0.0"
pkg_name="python3-pyarrow"
pkg_deps="python3>=3.9,python3-numpy>=1.25"
pkg_build_deps="python3>=3.9,python3-numpy>=1.25,arrow-cpp==18.0.0,python3-build,python3-setuptools,python3-wheel,python3-cython==3.0.12"
pkg_source_url="https://files.pythonhosted.org/packages/ec/41/6bfd027410ba2cc35da4682394fdc4285dc345b1d99f7bd55e96255d0c7d/pyarrow-18.0.0.tar.gz"
pkg_release_url=""
pkg_license="Apache-2.0"
pkg_support_archs="x86_64,aarch64,arm"
pkg_build_type="custom"
pkg_build_parallism="20"
pkg_force_clean_build=""
pkg_patch_files="patches/${pkg_version}/ohos-feature-selection-and-target-numpy.patch"

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
	apply_pkg_patches || return 1
}

custom_build() {
	local build_rc=0
	local arrow_prefix=""
	local numpy_prefix=""
	local numpy_root=""
	local numpy_include=""
	local cmake_options=""

	setup_pycrossenv || return 1
	"${PYCROSS_BUILD_PIP}" install "Cython==3.0.12" "setuptools-scm[toml]>=8,<9" || build_rc=$?

	if [ "$build_rc" -eq 0 ]; then
		arrow_prefix=$(get_pkg_dst_dir arrow-cpp) || build_rc=$?
	fi
	if [ "$build_rc" -eq 0 ]; then
		numpy_prefix=$(get_pkg_dst_dir python3-numpy) || build_rc=$?
	fi
	if [ "$build_rc" -eq 0 ]; then
		numpy_root="${numpy_prefix}/${OHOS_LIBDIR}/python${PY_VERSION}/site-packages/numpy"
		if [ -d "${numpy_root}/_core/include" ]; then
			numpy_include="${numpy_root}/_core/include"
		elif [ -d "${numpy_root}/core/include" ]; then
			numpy_include="${numpy_root}/core/include"
		else
			error "target NumPy headers not found below ${numpy_root}"
			build_rc=1
		fi
	fi

	if [ "$build_rc" -eq 0 ]; then
		cmake_options="-DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_CONFIG} -DOHOS_ARCH=${OHOS_ARCH} -DCMAKE_INSTALL_LIBDIR=${OHOS_LIBDIR} -DSSRVODKA_APPEND_CMAKE_PREFIX_PATH=${arrow_prefix} -DSSRVODKA_APPEND_CMAKE_FIND_ROOT_PATH=${HOST_PYTHON_DIST};${arrow_prefix};${numpy_prefix} -DPython3_EXECUTABLE=${PYCROSS_CROSS_PYTHON} -DPython3_INCLUDE_DIR=${HOST_PYTHON_DIST}/include/python${PY_VERSION} -DPython3_NumPy_INCLUDE_DIR=${numpy_include}"
		PYARROW_CPP_HOME="${arrow_prefix}" \
		PYARROW_CMAKE_OPTIONS="${cmake_options}" \
		PYARROW_CXXFLAGS="${CXXFLAGS}" \
		PYARROW_NUMPY_INCLUDE_DIR="${numpy_include}" \
		PYARROW_PARALLEL="${pkg_build_parallism}" \
		PYARROW_BUNDLE_ARROW_CPP=1 \
		PYARROW_WITH_PARQUET=0 \
		PYARROW_WITH_DATASET=0 \
		PYARROW_WITH_ACERO=0 \
		PYARROW_WITH_ORC=0 \
		PYARROW_WITH_GANDIVA=0 \
		PYARROW_WITH_PLASMA=0 \
		PYARROW_WITH_FLIGHT=0 \
		PYARROW_WITH_CSV=1 \
		PYARROW_WITH_JSON=0 \
		PYARROW_WITH_FILESYSTEM=0 \
		build_python_cross_package_active -v --no-deps --no-build-isolation --no-binary :all: . || build_rc=$?
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
}

################ self-defined functions (local) goes below ################
```

- [ ] **Step 3: Run syntax and metadata checks**

Run:

```bash
bash -n python3-pyarrow/BUILD python3-pyarrow/POSTINST
OHOS_SDK=/tools/ohos-sdk/18 OHOS_CPU=x86_64 \
  ./builder.sh --print-meta python3-pyarrow/BUILD
```

Expected: both commands exit zero; metadata reports version `18.0.0`, build type `custom`, runtime dependencies `python3>=3.9` and `python3-numpy>=1.25`, build dependency `arrow-cpp==18.0.0`, and the version-scoped patch path.

- [ ] **Step 4: Commit the package definition only**

```bash
git add python3-pyarrow/BUILD python3-pyarrow/POSTINST
git diff --cached --check
git commit -m "feat: define python3-pyarrow package"
```

Expected: the commit contains only the package definition and existing strict-mode `POSTINST`.

### Task 2: Adapt PyArrow Feature Selection and Target NumPy Discovery

**Files:**
- Create: `python3-pyarrow/patches/18.0.0/ohos-feature-selection-and-target-numpy.patch`

**Interfaces:**
- Consumes: `PYARROW_NUMPY_INCLUDE_DIR`, `PYARROW_WITH_CSV`, `PYARROW_WITH_JSON`, and `PYARROW_WITH_FILESYSTEM` from Task 1; `ARROW_CSV`, `ARROW_JSON`, and `ARROW_FILESYSTEM` from `ArrowConfig.cmake` supplied by `arrow-cpp`.
- Produces: `PYARROW_BUILD_CSV`, `PYARROW_BUILD_JSON`, and `PYARROW_BUILD_FILESYSTEM` CMake decisions; a `build_ext` path that does not import NumPy when the target include directory is explicit.

- [ ] **Step 1: Verify the clean 18.0.0 sdist exhibits the unsupported behavior**

Run:

```bash
check_root=$(mktemp -d /tmp/pyarrow-red.XXXXXX)
curl -fsSL \
  https://files.pythonhosted.org/packages/ec/41/6bfd027410ba2cc35da4682394fdc4285dc345b1d99f7bd55e96255d0c7d/pyarrow-18.0.0.tar.gz \
  -o "${check_root}/pyarrow.tar.gz"
tar -xzf "${check_root}/pyarrow.tar.gz" -C "${check_root}"
python3 - "${check_root}/pyarrow-18.0.0" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
cmake = (root / "CMakeLists.txt").read_text()
setup = (root / "setup.py").read_text()
assert "define_option(CSV" in cmake
assert "define_option(JSON" in cmake
assert "define_option(FILESYSTEM" in cmake
assert "os.environ.get('PYARROW_NUMPY_INCLUDE_DIR')" in setup
PY
```

Expected: assertion failure on `define_option(CSV`, proving upstream ignores the requested CSV/JSON/filesystem environment switches and still imports NumPy unconditionally.

- [ ] **Step 2: Create the version-scoped upstream patch**

Create `python3-pyarrow/patches/18.0.0/ohos-feature-selection-and-target-numpy.patch` with this content:

```diff
--- a/setup.py
+++ b/setup.py
@@ -108,2 +108,4 @@
-        import numpy
-        numpy_incl = numpy.get_include()
+        numpy_incl = os.environ.get('PYARROW_NUMPY_INCLUDE_DIR')
+        if not numpy_incl:
+            import numpy
+            numpy_incl = numpy.get_include()
--- a/CMakeLists.txt
+++ b/CMakeLists.txt
@@ -305,0 +306,3 @@
+define_option(CSV "Build the PyArrow CSV integration" ARROW_CSV)
+define_option(FILESYSTEM "Build the PyArrow filesystem integration" ARROW_FILESYSTEM)
+define_option(JSON "Build the PyArrow JSON integration" ARROW_JSON)
@@ -432 +435,4 @@
-if(ARROW_CSV)
+if(PYARROW_BUILD_CSV)
+  if(NOT ARROW_CSV)
+    message(FATAL_ERROR "You must build Arrow C++ with ARROW_CSV=ON")
+  endif()
@@ -436 +442,4 @@
-if(ARROW_FILESYSTEM)
+if(PYARROW_BUILD_FILESYSTEM)
+  if(NOT ARROW_FILESYSTEM)
+    message(FATAL_ERROR "You must build Arrow C++ with ARROW_FILESYSTEM=ON")
+  endif()
@@ -643,8 +652,13 @@
-set(CYTHON_EXTENSIONS
-    lib
-    _compute
-    _csv
-    _feather
-    _fs
-    _json
-    _pyarrow_cpp_tests)
+set(CYTHON_EXTENSIONS lib _compute _feather _pyarrow_cpp_tests)
+if(PYARROW_BUILD_CSV)
+  list(APPEND CYTHON_EXTENSIONS _csv)
+endif()
+if(PYARROW_BUILD_FILESYSTEM)
+  list(APPEND CYTHON_EXTENSIONS _fs)
+endif()
+if(PYARROW_BUILD_JSON)
+  if(NOT ARROW_JSON)
+    message(FATAL_ERROR "You must build Arrow C++ with ARROW_JSON=ON")
+  endif()
+  list(APPEND CYTHON_EXTENSIONS _json)
+endif()
```

- [ ] **Step 3: Apply the patch to a clean sdist and verify the intended behavior markers**

Run:

```bash
check_root=$(mktemp -d /tmp/pyarrow-green.XXXXXX)
curl -fsSL \
  https://files.pythonhosted.org/packages/ec/41/6bfd027410ba2cc35da4682394fdc4285dc345b1d99f7bd55e96255d0c7d/pyarrow-18.0.0.tar.gz \
  -o "${check_root}/pyarrow.tar.gz"
tar -xzf "${check_root}/pyarrow.tar.gz" -C "${check_root}"
patch -d "${check_root}/pyarrow-18.0.0" -p1 \
  < python3-pyarrow/patches/18.0.0/ohos-feature-selection-and-target-numpy.patch
python3 - "${check_root}/pyarrow-18.0.0" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
cmake = (root / "CMakeLists.txt").read_text()
setup = (root / "setup.py").read_text()
for option in ("CSV", "JSON", "FILESYSTEM"):
    assert f"define_option({option}" in cmake
    assert f"PYARROW_BUILD_{option}" in cmake
assert "list(APPEND CYTHON_EXTENSIONS _csv)" in cmake
assert "list(APPEND CYTHON_EXTENSIONS _json)" in cmake
assert "list(APPEND CYTHON_EXTENSIONS _fs)" in cmake
assert "os.environ.get('PYARROW_NUMPY_INCLUDE_DIR')" in setup
PY
```

Expected: patch applies with no fuzz or rejects and all assertions pass.

- [ ] **Step 4: Run package patch lint and syntax checks**

Run:

```bash
bash -n python3-pyarrow/BUILD
./lint-patches.sh --strict
```

Expected: both commands exit zero and strict patch lint reports no unowned or missing package patch.

- [ ] **Step 5: Commit the source adaptation**

```bash
git add python3-pyarrow/patches/18.0.0/ohos-feature-selection-and-target-numpy.patch
git diff --cached --check
git commit -m "fix: adapt pyarrow for trimmed arrow build"
```

Expected: the commit contains only the version-scoped patch.

### Task 3: Generate Metadata and Verify the Local Build

**Files:**
- Modify: `PKG_INDEX.json`

**Interfaces:**
- Consumes: the completed `python3-pyarrow` package, repository package index generator, parent dependency resolver, and generated wheel/artifact manifest.
- Produces: a machine-readable `python3-pyarrow` package index entry and fresh local verification evidence.

- [ ] **Step 1: Generate and inspect the package index**

Run:

```bash
./gen-pkg-index.sh
python3 - <<'PY'
import json

with open("PKG_INDEX.json", encoding="utf-8") as stream:
    packages = json.load(stream)
entry = next(item for item in packages if item["name"] == "python3-pyarrow")
assert entry["version"] == "18.0.0"
assert entry["build_file"] == "python3-pyarrow/BUILD"
assert "arrow-cpp==18.0.0" in entry["build_deps"]
assert entry["patch_files"] == [
    "patches/18.0.0/ohos-feature-selection-and-target-numpy.patch"
]
PY
git diff --check -- PKG_INDEX.json
```

Expected: all assertions pass and the index diff has no whitespace errors.

- [ ] **Step 2: Run the dependency-resolved local x86_64 build**

Run from the repository parent:

```bash
local_prefix=$(mktemp -d /tmp/ohloha-pyarrow-prefix.XXXXXX)
OHOS_SDK=/tools/ohos-sdk/18 OHOS_CPU=x86_64 \
  ./scripts/build_and_install.sh --jobs 16 --prefix "${local_prefix}" \
  python3-pyarrow
```

Expected: exit zero after resolving and building `python3-pyarrow` and its dependency closure. This command intentionally performs no `kiwi` or aarch64 build.

- [ ] **Step 3: Inspect the built package feature set and bundled libraries**

Run from `ohloha_pkgs`:

```bash
pyarrow_dist=$(find . -maxdepth 1 -type d -name 'dist.x86_64.python3-pyarrow-18.0.0' -print -quit)
test -n "${pyarrow_dist}"
site_packages="${pyarrow_dist}/lib/python3.12/site-packages"
test -f "${site_packages}/pyarrow/lib.cpython-312-x86_64-linux-ohos.so"
test -f "${site_packages}/pyarrow/_csv.cpython-312-x86_64-linux-ohos.so"
test ! -e "${site_packages}/pyarrow/_json.cpython-312-x86_64-linux-ohos.so"
test ! -e "${site_packages}/pyarrow/_fs.cpython-312-x86_64-linux-ohos.so"
find "${site_packages}/pyarrow" -maxdepth 1 -type f \
  \( -name 'libarrow.so*' -o -name 'libarrow_python.so*' \) -print
patchelf --print-needed \
  "${site_packages}/pyarrow/lib.cpython-312-x86_64-linux-ohos.so"
```

Expected: core and CSV extensions exist; JSON and filesystem extensions do not; bundled `libarrow` and `libarrow_python` files are printed; the core extension's needed libraries resolve to bundled names plus expected Python/system libraries.

- [ ] **Step 4: Run the final verification suite and inspect repository scope**

Run:

```bash
bash -n python3-pyarrow/BUILD python3-pyarrow/POSTINST
OHOS_SDK=/tools/ohos-sdk/18 OHOS_CPU=x86_64 \
  ./builder.sh --print-meta python3-pyarrow/BUILD >/tmp/python3-pyarrow-meta.json
./lint-patches.sh --strict
git diff --check
git status --short
```

Expected: syntax, metadata, patch lint, and whitespace checks exit zero. `git status --short` lists only the intended `PKG_INDEX.json` change plus pre-existing unrelated user work and ignored build outputs; no generated output is staged.

- [ ] **Step 5: Commit the generated package index only**

```bash
git add PKG_INDEX.json
git diff --cached --check
git diff --cached --name-only
git commit -m "chore: index python3-pyarrow"
```

Expected: `git diff --cached --name-only` prints only `PKG_INDEX.json` before the commit.
