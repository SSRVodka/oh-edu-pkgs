# Arrow C++ OHOS Dependency Cache Design

## Scope

Fix the Arrow C++ 23.0.0 OHOS package without changing its current linkage model. Arrow remains a shared library whose bundled third-party compiled code is linked statically into Arrow's shared objects. Header-only dependencies remain build inputs only.

This change does not split bundled dependencies into independent runtime packages and does not modify `builder.sh` or `setup2.sh`.

## Dependency Ownership

Keep `ARROW_DEPENDENCY_SOURCE=BUNDLED`. Arrow's enabled feature set builds or consumes these bundled dependencies:

- compiled static inputs: LZ4, Zstandard, zlib, RE2, utf8proc, Thrift, and Boost.Container;
- header-only inputs: xsimd, RapidJSON, and the remaining used Boost components;

Because these inputs are absorbed into Arrow's shared libraries, they are not Arrow runtime dependencies and must not be added to `pkg_deps`. Remove the existing `libz` runtime and build dependency declarations because this configuration selects bundled zlib.

## Archive Cache

Remove `arrow-cpp/thirdparty-cache` and all package-local download code. For each required upstream archive, derive its existing content-addressed path with `source_archive_path_for_url`, which maps the URL into `.ohloha/downloads/sha256-<url-digest>.archive`.

Add a small package-local helper that:

1. resolves the content-addressed cache path;
2. downloads into a temporary file;
3. publishes it atomically under the existing `download-<url-digest>` lock;
4. fails the build on download failure;
5. validates the archive against Arrow's upstream SHA-256 value;
6. exports the corresponding `ARROW_*_URL=file://...` variable.

The helper must reuse repository locking and cache variables, quote paths, and never write beside `BUILD`. Arrow's own `URL_HASH` validation remains enabled; the Boost checksum bypass and modified Boost archive are removed.

## OHOS Atomic Patch

Add a package-owned patch under `arrow-cpp/patches/23.0.0/` and declare it in `pkg_patch_files`. Apply it once with `apply_pkg_patches`.

The patch changes Arrow's Raspbian `armv7` condition in `cpp/src/arrow/CMakeLists.txt` so it does not append `-latomic` when targeting OHOS. This is the owning source location: the current condition treats every Linux/armv7 toolchain as Raspbian, while OHOS reports Linux/armv7 but has no `libatomic` archive.

The same patch makes the current OHOS Boost.Locale adjustment explicit in `ThirdpartyToolchain.cmake`: do not request or alias Boost.Locale for OHOS. Use the pristine upstream Boost archive and retain its SHA-256 validation instead of mutating the archive and bypassing its checksum.

Delete the code that creates an empty archive inside `${OHOS_SDK}`. No architecture-specific wrapper or SDK mutation remains.

## Validation

Automated static checks will first fail against the current package and then pass after the change. They will assert:

- no path under `arrow-cpp/thirdparty-cache` is referenced or tracked;
- no command writes beneath `${OHOS_SDK}`;
- `pkg_patch_files` declares the OHOS patch;
- the patch excludes OHOS from the Raspbian `-latomic` condition;
- bundled dependency URLs use `.ohloha/downloads` through the repository cache API;
- failed downloads are not ignored;
- syntax and `--print-meta` succeed.

Build verification will run Arrow 23 for available OHOS architectures, prioritizing the previously failing architecture. Successful artifacts will be inspected with `readelf -d`: bundled dependencies and `libatomic` must not appear in `DT_NEEDED`. Build logs must not contain writes into the SDK or package-local archive downloads.

Verification reporting will distinguish local static checks, direct `builder.sh` builds, and remote multi-architecture builds.
