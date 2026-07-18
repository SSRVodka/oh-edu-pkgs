# Verification and Debugging

## Lightweight Verification

Run syntax checks after script edits:

```bash
bash -n builder.sh setup2.sh
bash -n <pkg>/BUILD
```

Check package metadata:

```bash
OHOS_SDK=/tools/ohos-sdk/18 OHOS_CPU=aarch64 ./builder.sh --print-meta <pkg>/BUILD
```

If dependencies changed, ensure `pkg_deps`, `pkg_build_deps`, test topology, and package index expectations agree.

## Build Verification

Prefer parent dependency resolution for real package validation:

```bash
cd ..
OHOS_SDK=/tools/ohos-sdk/18 OHOS_CPU=aarch64 ./scripts/build_and_install.sh --jobs 16 --prefix /root/workspace/out <pkg>
```

Do not use `--jobs 1` for normal testing. Use at least 10-20 jobs unless intentionally isolating a race.

Direct `builder.sh` is useful for fast feedback only when dependencies are manually provided in topological order:

```bash
OHOS_SDK=/tools/ohos-sdk/18 OHOS_CPU=aarch64 ./builder.sh --cpu=aarch64 dep1/BUILD dep2/BUILD <pkg>/BUILD
```

## Debugging Sequence

1. Read `.ohloha/logs/<arch>/<pkg>/<version>/build.log`.
2. Find the first failing command.
3. Run that primitive command directly when possible.
4. Classify which layer owns the failure:
   - package hook: package-specific target deps/flags.
   - `setup2.sh`: shared host tools, wrappers, SDK/toolchain setup.
   - `builder.sh`: crossenv lifecycle, build helpers, dependency resolution consumption.
   - parent Go project: dependency closure, resolved-deps, DAG scheduling.
   - upstream patch: invalid upstream build-system behavior with no supported override.
5. Fix the owning layer only.
6. Re-run the primitive command, then the package build.

## Environment Checks

For native Python packages, verify exact crossenv commands:

```bash
.ohloha/crossenv/18/aarch64/cross/bin/python3-config --includes
.ohloha/crossenv/18/aarch64/cross/bin/python3-config --ldflags
```

If wheel metadata unexpectedly reports `0.0.0`, inspect `pyproject.toml` for `dynamic = ["version"]` and its provider. Confirm the provider is importable from the PEP 517 build side, not merely `${HOST_TOOLS_PYTHON}`, and check whether the downloaded source contains the VCS metadata the provider expects. For `setuptools_scm`, verify any `SETUPTOOLS_SCM_PRETEND_VERSION_FOR_<DIST_NAME>` override uses the normalized distribution name (uppercase, non-alphanumeric characters replaced with underscores).

For target linker issues, check whether the failing command is raw `ld.lld`, a compiler driver, or a wrapper. Do not change global Python linkage to hide a missing package-local `-L` path.

For host-loaded libraries such as `libclang.so`, verify that the library is for the build host, not the OHOS target, unless the failing target binary actually links it.

## Reporting

Report the highest verification level actually completed:

- syntax and metadata only.
- primitive command reproduced and fixed.
- direct `builder.sh` package build.
- parent `build_and_install.sh` package build.
- deployed/installed package.

Do not overstate a migration as complete when only an earlier verification layer passed.
