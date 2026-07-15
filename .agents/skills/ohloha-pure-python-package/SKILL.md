---
name: ohloha-pure-python-package
description: Migrate pure-Python PyPI packages into the ohloha_pkgs OpenHarmony package repository. Use when adding or updating python3-* BUILD files for PyPI sdists, deriving pkg_deps/pkg_build_deps from pyproject.toml dependencies, using pkgs-create.sh templates, or validating pure-python package metadata in ohloha_pkgs.
---

# Ohloha Pure Python Package

## Workflow

Use this workflow inside an `ohloha_pkgs` checkout.

1. Read the repository `AGENTS.md` rules first. If touching root scripts or unclear about build-system refactors, also read `TODO.md` and `DESIGN.md`.
2. Inspect nearby examples before editing: prefer `python3-typing-extensions`, `python3-typing-inspection`, `python3-annotated-types`, and any package with the same build backend.
3. Confirm whether the package directory already exists with `rg --files | rg '^python3-<name>/'`.
4. For every new package, run `./pkgs-create.sh python3-<name>`. Do not create the package directory by copying `.template` manually.
5. Fetch the PyPI sdist metadata and read its `pyproject.toml`, not just PyPI's rendered dependency summary.
6. Fill `BUILD` as a pure-python package unless the source contains native extensions or a Rust/PyO3 backend.
7. Validate with `bash -n <pkg>/BUILD` and `./builder.sh --print-meta <pkg>/BUILD`.
8. If adding dependencies or a new verification chain, update `test-deps.sh` with a separate topology array unless the existing preset should intentionally expand.

For detailed dependency mapping and field rules, read `references/migration-checklist.md`.

## Dependency Rules

Derive `pkg_deps` from `project.dependencies` for the target Python version. For current ohloha Python migrations, assume Python 3.12 unless the user says otherwise.

- Ignore dependencies guarded by markers that are false for Python 3.12, such as `python_version < "3.11"` or Windows-only `platform_system == "Windows"`.
- Keep dependencies guarded by `python_version < "3.13"` because Python 3.12 satisfies them.
- Convert PyPI names to repository package names, normally `foo-bar` -> `python3-foo-bar`.
- If a declared dependency is missing from the repo, migrate it too or clearly state the missing package. Do not leave a dependency chain knowingly broken.
- Put runtime dependencies in `pkg_deps`. Put the same Python package dependencies plus `python3-build,python3-setuptools` in `pkg_build_deps` for the local pure-python pattern.
- For multi-part constraints on the same dependency, use the repo-compatible comma continuation form, e.g. `python3-httpx>=0.23.0,<1`, not `python3-httpx>=0.23.0,python3-httpx<1`.

## BUILD Pattern

For pure-Python packages, prefer the established explicit hook pattern:

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

Use `--no-deps` to prevent pip from downloading runtime dependencies during cross builds. Do not use `--no-build-isolation` unless the backend must be preinstalled into the crossenv build side and the BUILD hook explicitly does that.

## Validation

At minimum run:

```bash
bash -n python3-<name>/BUILD
./builder.sh --print-meta python3-<name>/BUILD
```

When practical, build the package and its dependencies in topological order:

```bash
./builder.sh dep1/BUILD dep2/BUILD python3-<name>/BUILD
```

If a full build would require large native or Rust/PyO3 prerequisites, report the exact validation level completed instead of overstating success.
