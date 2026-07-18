# Package Categories

## Native Libraries and Binaries

Examples include C/C++ libraries, command-line tools, multimedia stacks, database/client libraries, and X/graphics libraries.

Use this category when the package is not a Python package and primarily builds target native artifacts.

Migration rules:

- Prefer `pkg_build_type="autotools"`, `cmake`, or `meson` over `custom` when upstream supports it.
- Use `pkg_build_*` fields and shared helpers before writing hooks.
- Put runtime target dependencies in `pkg_deps` and build-time target dependencies in `pkg_build_deps`.
- Let helpers add dependency include/lib/pkg-config/CMake paths.
- Configure reusable compiler/linker/tool wrappers in `setup2.sh`.
- Use package-local patches under `<pkg>/patches/<pkg_version>/` for upstream build fixes.

Check similar packages such as `openssl`, `ffmpeg`, `grpc`, `geos`, `libxslt`, `xorg`, and existing CMake/Meson/autotools packages.

## Pure Python Packages

Use `ohloha-pure-python-package`.

This category is for Python packages whose sdist builds no native extension and does not require target C/Rust compilation.

Typical pattern:

```bash
pkg_build_type="pure-python"

custom_build() {
	build_python_cross_package -v --no-deps . || return 1
	_custom_build_continue=false
}

postbuilt_hook() {
	install_current_python_wheelhouse_to_target_site_packages
}
```

Keep runtime dependencies in `pkg_deps`; include Python build helpers such as `python3-build` and `python3-setuptools` according to the local pure-Python pattern.

## Native Python Packages

Use this category when a `python3-*` package builds C/C++ extensions or bundled native libraries through setuptools, Cython, SWIG, pybind11, cppyy, scikit-build, Meson, CMake, or pipcl.

These non-Rust native Python packages normally remain `pkg_build_type="custom"` because their PEP 517 backends and native dependency controls vary. Use this lifecycle unless a simpler existing helper is sufficient:

```bash
custom_build() {
	local build_rc=0

	setup_pycrossenv || return 1

	# Resolve target dependencies and set package-specific flags here. If build
	# isolation is disabled, install every backend into ${PYCROSS_BUILD_PIP}.
	build_python_cross_package_active \
		-v --no-deps --no-binary :all: . \
	|| build_rc=$?

	destroy_pycrossenv || {
		[ "$build_rc" -eq 0 ] && build_rc=1
	}
	_custom_build_continue=false
	return "$build_rc"
}

postbuilt_hook() {
	install_current_python_wheelhouse_to_target_site_packages
}
```

`setup_pycrossenv` enters the shared crossenv and establishes target Python/NumPy flags. Add dependency paths and backend-specific variables after it. `build_python_cross_package_active` owns wheel construction and wheelhouse bookkeeping; reuse it instead of reproducing its pip/wheel commands in package hooks. `destroy_pycrossenv` must run on success and failure to leave the environment and release its lock. The post-build hook extracts the wheel into this package's target prefix.

For packages needing no preparation after entering crossenv, use `build_python_cross_package ...` instead; it already wraps setup, active build, and cleanup. Do not call `setup_pycrossenv` around that wrapper.

Rules:

- Usually use `pkg_build_type="custom"` and call `setup_pycrossenv` explicitly.
- Reuse `build_python_cross_package`, `build_python_cross_package_active`, and `install_current_python_wheelhouse_to_target_site_packages` whenever their contracts fit. Do not copy their wheel-directory, archive, or installation logic into individual packages.
- After cross-compiling the wheel, do not explicitly install the package into the shared crossenv with `${PYCROSS_CROSS_PIP}`. In particular, package hooks must not run commands such as `${PYCROSS_CROSS_PIP} install --force-reinstall --no-deps --no-index --find-links "$wheel_dir" "name==${pkg_version}"`; that leaks package state into later builds. Install the wheel only into `${target_root_with_pkgname}` through `install_current_python_wheelhouse_to_target_site_packages` in `postbuilt_hook`.
- Keep PEP 517 build isolation by default. Use `--no-deps` to block runtime dependency downloads.
- Preserve `--no-binary :all:` unless policy explicitly changes.
- Use `--no-build-isolation` only when the hook installs every required build backend/plugin into `${PYCROSS_BUILD_PIP}` and documents why. Installing them only into `${HOST_TOOLS_PYTHON}` is insufficient because PEP 517 runs through crossenv.
- For dynamic versions provided by `setuptools_scm`, treat a wheel named `0.0.0` as missing/inactive SCM integration, not as a cross-compiler result. With `--no-build-isolation`, install `setuptools_scm` into `${PYCROSS_BUILD_PIP}`. When building a GitHub tag archive without `.git`, also set the package-normalized `SETUPTOOLS_SCM_PRETEND_VERSION_FOR_<DIST_NAME>` to `${pkg_version}`; do not rely on an absent tag or a stale upstream fallback.
- If extension tooling derives `python3-config` from `sys.executable`, it may select `.ohloha/crossenv/<api>/<cpu>/cross/bin/python3-config`; make that wrapper correct instead of patching around symptoms.
- Declare target libraries that appear in `python3-config --ldflags`, such as `libgettext` for `-lintl`.
- Add target `-I`/`-L` paths in the package hook, not globally.
- Manage host tools such as SWIG, CMake, Meson, and host-loaded `libclang.so` in `setup2.sh`/host wrappers.

Useful examples include `python3-cffi`, `python3-lxml`, `python3-matplotlib`, `python3-opencv`, and `python3-pyarrow`. Treat older direct-`pip install` hooks such as `python3-netifaces` as legacy patterns, not templates for new migrations.

## Rust-Python Packages

Use this category when the Python package builds Rust extensions through PyO3, maturin, setuptools-rust, or a Rust-heavy backend.

Rules:

- Rust toolchain setup is a host prerequisite, not package `BUILD` logic.
- Manage `maturin` and `setuptools-rust` as host tools.
- Use `setup_pyo3_rust_cross_env` or the repository's Rust/PyO3 helper path instead of hand-written cargo target environments.
- Keep Python crossenv linkage semantics intact, including `-lpython${PY_VERSION}` when required by the OHOS runtime model.
- Separate cargo crate downloads/cache behavior from target runtime dependencies.

Useful examples include packages similar to `python3-pydantic_core`, `python3-rpds`, `python3-jiter`, and Rust-backed crypto or parser packages.
