# Pure-Python Migration Checklist

## Gather Source Metadata

Use current PyPI metadata and the sdist `pyproject.toml`.

Useful Python snippet:

```python
import json, tarfile, tempfile, tomllib, urllib.request

name = "example"
data = json.load(urllib.request.urlopen(f"https://pypi.org/pypi/{name}/json", timeout=30))
version = data["info"]["version"]
sdist = next(f for f in data["releases"][version] if f.get("packagetype") == "sdist")
path = tempfile.mktemp(suffix=".tar.gz")
urllib.request.urlretrieve(sdist["url"], path)
with tarfile.open(path) as tf:
    member = next(m for m in tf.getmembers() if m.name.count("/") == 1 and m.name.endswith("/pyproject.toml"))
    pyproject = tomllib.loads(tf.extractfile(member).read().decode())
print(version, sdist["url"], pyproject.get("project", {}).get("dependencies"), pyproject.get("build-system"))
```

Prefer the latest stable PyPI sdist unless the user requested a specific version.

## Fill BUILD Fields

- `pkg_version`: upstream version from the sdist release.
- `pkg_name`: repository package name, usually `python3-<pypi-normalized-name>`.
- `pkg_source_url`: sdist URL, not the wheel URL.
- `pkg_release_url`: leave empty unless the package convention needs it.
- `pkg_license`: use SPDX-like value when PyPI provides one; otherwise use the nearest clear license string from metadata.
- `pkg_support_archs`: keep template default unless package-specific constraints require changing it.
- `pkg_build_type`: use `pure-python` only when no native extension is built.
- `pkg_patch_files`: leave empty unless adding package-local patches.

Keep `setup()` metadata-only. Do not call `get_pkg_dst_dir`, inspect target roots, or expand build-time flags in `setup()`.

## Dependency Mapping Examples

For Python 3.12:

- `colorama; platform_system == "Windows"` -> omit for OHOS.
- `exceptiongroup >= 1.0.2; python_version < "3.11"` -> omit.
- `typing_extensions >= 4.5; python_version < "3.13"` -> include as `python3-typing-extensions>=4.5`.
- `httpx>=0.23.0, <1` -> `python3-httpx>=0.23.0,<1`.
- `httpcore==1.*` -> `python3-httpcore==1.*`.

If a dependency is optional extra-only, do not add it unless it is in `project.dependencies` for the default install or the user requested that extra.

## Build Backend Notes

The ohloha pure-python pattern normally keeps PEP 517 build isolation and passes `--no-deps`. Build backends such as `hatchling`, `flit_core`, `setuptools_scm`, and `hatch-fancy-pypi-readme` are build-system requirements, not runtime dependencies.

Do not add backend packages to `pkg_deps` just because they appear in `[build-system].requires`. Add them to package metadata only if the repo's build helpers actually require that for the chosen pattern and the package fails without it.

## Topology and Tests

When adding several packages, order them from leaves to final package:

1. Runtime leaves with only `python3` dependency.
2. Shared libraries such as `python3-idna`, `python3-certifi`, `python3-h11`.
3. Mid-level packages such as `python3-httpcore`, `python3-anyio`, `python3-httpx`.
4. Final package such as `python3-openai`.

Add a named array to `test-deps.sh` for a new chain. Avoid adding it to `all_deps` unless the user asks or existing policy expects it.

## Final Checks

- Run `bash -n` for changed BUILD files and `test-deps.sh` if edited.
- Run `./builder.sh --print-meta` for each new BUILD.
- Run `./gen-pkg-index.sh` when the repo expects `PKG_INDEX.json` refreshes.
- Check `git status --short` and make sure no `.ohloha/`, `.staging*`, `dist*`, `deploy/`, wheels, downloaded sdists, or generated meson files are staged or reported as intended changes.
