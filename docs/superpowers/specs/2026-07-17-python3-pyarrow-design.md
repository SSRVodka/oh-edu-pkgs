# Python3 PyArrow 18.0.0 Migration Design

## Goal

Add an OpenHarmony package definition for `python3-pyarrow` 18.0.0 that
cross-compiles against the repository's trimmed `arrow-cpp` 18.0.0 package,
bundles the required Arrow shared libraries in the wheel, and exposes only the
features supported by that Arrow build.

## Scope

The migration owns `python3-pyarrow/BUILD`, its `POSTINST`, and version-scoped
patches under `python3-pyarrow/patches/18.0.0/`. The existing `arrow-cpp`
package is an input and will not be modified.

The feature set is:

- enabled: CSV;
- disabled: JSON, filesystem, Parquet, Dataset, Acero, ORC, Gandiva, Plasma,
  and Flight;
- Arrow C++ shared libraries are bundled into the PyArrow wheel.

Verification is local. No aarch64 build on `kiwi` is required.

## Package Metadata and Dependency Ownership

The package uses the official PyPI `pyarrow-18.0.0` sdist and
`pkg_build_type="custom"`.

Runtime target dependencies are Python 3.9 or newer and NumPy 1.25 or newer.
`arrow-cpp==18.0.0` is a build dependency because its headers, libraries, and
CMake package metadata are consumed while building PyArrow. The Arrow shared
libraries are bundled in the wheel, so the installed PyArrow package does not
need a separate runtime `arrow-cpp` package dependency.

Build dependencies also include the repository's Python build, setuptools,
wheel, and Cython packages. Host-executable backend requirements that are not
target packages, notably `setuptools-scm`, are installed through
`${PYCROSS_BUILD_PIP}` after entering crossenv.

NumPy is deliberately not installed through `${PYCROSS_BUILD_PIP}`. The
resolved target NumPy package is both the runtime ABI dependency and the source
of NumPy headers. This avoids accidentally compiling against host-generated
NumPy configuration headers.

## Source Adaptation

PyArrow 18.0.0 unconditionally includes its `_csv`, `_json`, and `_fs` Cython
extensions even though the corresponding Arrow C++ capabilities can be
disabled. A version-scoped patch will make those entries conditional on
`ARROW_CSV`, `ARROW_JSON`, and `ARROW_FILESYSTEM`. With the existing Arrow
configuration, `_csv` is built and `_json` and `_fs` are omitted. The public
`pyarrow.json` and `pyarrow.fs` modules then fail with the normal optional-module
`ImportError` behavior when explicitly imported, while importing core PyArrow
remains valid.

The same patch will allow `setup.py` to consume an explicit NumPy include
directory supplied by the package hook. This bypasses its unconditional
build-time `import numpy`. CMake receives the resolved target NumPy include
directory through `Python3_NumPy_INCLUDE_DIR`, so its `FindPython3` NumPy
component creates `Python3::NumPy` with target headers without importing the
target NumPy extension modules on the build host.

The patch will be declared in `pkg_patch_files` and applied through the shared
package patch helper. No build-time `sed` rewriting is used.

## Build Flow

The `custom_build` hook will:

1. enter the shared Python crossenv;
2. install host-executable Cython and setuptools-scm backend requirements on
   the build side;
3. resolve `arrow-cpp` and `python3-numpy` with `get_pkg_dst_dir`;
4. derive the target NumPy include directory from the resolved NumPy package;
5. pass the OHOS CMake toolchain, Arrow prefix, target Python paths, and target
   NumPy include directory to PyArrow's CMake invocation;
6. set `PYARROW_BUNDLE_ARROW_CPP=1`, enable CSV, and disable JSON, filesystem,
   Parquet, Dataset, Acero, ORC, Gandiva, Plasma, and Flight;
7. build a source wheel with `--no-deps`, `--no-build-isolation`, and
   `--no-binary :all:`; and
8. leave crossenv on both success and failure while preserving the original
   build error.

`postbuilt_hook` installs the produced wheelhouse into the package's target
site-packages directory. Feature and CMake environment variables are scoped to
the build invocation so they do not leak into another package.

## Failure Handling

Every dependency resolution, backend installation, wheel build, crossenv
teardown, and wheel installation failure returns a nonzero status. If the build
fails and crossenv teardown also fails, the original build failure remains the
primary result. If only teardown fails, the hook reports that failure.

No hook uses `$PWD`, relative `cd`, an unversioned `dist.<cpu>.<pkg>` path, or a
global mutable build directory.

## Verification

Verification proceeds in increasing cost:

1. demonstrate that the initial scaffold fails `builder.sh --print-meta` due to
   missing metadata;
2. run `bash -n python3-pyarrow/BUILD python3-pyarrow/POSTINST`;
3. run `builder.sh --print-meta` and confirm version, dependency, source, build
   type, and patch metadata;
4. apply the package patch to a clean PyArrow 18.0.0 source tree and assert that
   CSV remains conditional while JSON and filesystem extensions are omitted
   when their Arrow options are false;
5. run `lint-patches.sh --strict`;
6. generate `PKG_INDEX.json` and confirm the PyArrow entry without disturbing
   unrelated workspace changes; and
7. run a local x86_64 dependency-resolved build, then inspect the wheel and
   installed ELF dependencies to confirm that core PyArrow and CSV were built,
   JSON/filesystem extensions were not built, and Arrow shared libraries were
   bundled.

If the local build is blocked by an external download or unavailable host
prerequisite, the final report will stop at the highest verification level that
actually passed and identify the first failing command from the package log.
