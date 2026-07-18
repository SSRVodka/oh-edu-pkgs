---
name: ohloha-package-migration
description: Migrate, review, or debug packages in the ohloha_pkgs OpenHarmony/OHOS package repository across native libraries/binaries, pure Python packages, native Python extension packages, and Rust-Python packages. Use when adding or fixing BUILD files, classifying package type, deciding host/cross/OHOS dependency ownership, or validating package builds with builder.sh or the parent build_and_install.sh workflow.
---

# Ohloha Package Migration

## Workflow

Use this inside an `ohloha_pkgs` checkout.

1. Read `AGENTS.md`. If touching `builder.sh`, `setup2.sh`, root scripts, or the parent Go project, also read `TODO.md` and `DESIGN.md`.
2. Classify the package before editing. Use `references/package-categories.md`.
3. For pure Python packages, use `ohloha-pure-python-package` for PyPI metadata and dependency mapping.
4. For non-pure packages, inspect nearby working examples in the same category before editing.
5. Keep `setup()` metadata-only. Resolve dependency paths, target flags, and generated paths in build-stage hooks.
6. Separate dependency ownership:
   - host build tools run on the build machine and belong in `setup2.sh`, host venv, or tool wrappers.
   - crossenv build-side Python packages are PEP 517 backend/build imports.
   - crossenv target-side commands include target Python and `python3-config` wrappers.
   - OHOS target libraries belong in `pkg_deps`/`pkg_build_deps` and package-local flags.
7. Prefer shared helpers and wrappers over package-local ad hoc tool installation.
8. Verify small facts first, then run a package build. Use `references/verification-debugging.md`.

## Category Rules

Read only the relevant section of `references/package-categories.md` after classification.

- **Native libraries/binaries**: use Autotools/CMake/Meson helpers and target dependency paths supplied by the build system.
- **Pure Python packages**: use `ohloha-pure-python-package`; keep build isolation by default and use `--no-deps`.
- **Native Python packages**: read the full lifecycle in `references/package-categories.md`; keep non-Rust backend/dependency preparation between `setup_pycrossenv` and `build_python_cross_package_active`, always destroy crossenv, and install the resulting wheelhouse in `postbuilt_hook`.
- **Rust-Python packages**: use Rust/PyO3 helpers; do not put rustup/cargo setup or host tool installs in package `BUILD`.

## Common Checks

For changed root scripts or packages:

```bash
bash -n builder.sh setup2.sh
bash -n <pkg>/BUILD
OHOS_SDK=/tools/ohos-sdk/18 OHOS_CPU=aarch64 ./builder.sh --print-meta <pkg>/BUILD
```

For dependency-resolved verification, prefer the parent project:

```bash
cd ..
OHOS_SDK=/tools/ohos-sdk/18 OHOS_CPU=aarch64 ./scripts/build_and_install.sh --jobs 16 --prefix /root/workspace/out <pkg>
```

For faster debugging, direct `builder.sh` is valid only with dependencies in topological order or a correct resolved-deps file.

## Non-Negotiables

- Do not install random host tools in package `BUILD` files.
- Reuse the existing Python wheel/crossenv helpers; do not duplicate their implementation in package hooks.
- Do not explicitly install a newly cross-compiled package into the shared crossenv with `${PYCROSS_CROSS_PIP}`. Package output belongs under `${target_root_with_pkgname}` via the wheelhouse installation helper.
- Do not remove `--no-binary :all:` merely to avoid source builds.
- Do not add `--no-build-isolation` unless backend requirements are intentionally installed into the crossenv build side.
- Do not remove or weaken `-lpython${PY_VERSION}` from Python crossenv linkage.
- Do not rely on old unversioned `dist.<cpu>.<pkg>` paths.
- Do not claim a package migrated until the exact relevant verification level has passed.
