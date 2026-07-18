# Arrow C++ OHOS Dependency Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep Arrow 23's third parties bundled and statically linked while caching pristine archives under `.ohloha/downloads` and removing the invalid OHOS SDK `libatomic.a` mutation.

**Architecture:** `arrow-cpp/BUILD` will prepare Arrow's bundled archive URLs through the repository's existing URL-addressed download cache and locking API. A declared package patch will adjust Arrow's CMake logic for OHOS, excluding OHOS from the Raspbian `-latomic` rule and omitting Boost.Locale without modifying the upstream Boost archive.

**Tech Stack:** Bash strict mode, Arrow CMake, unified patches, `builder.sh`, OHOS Clang/LLD, ELF `readelf`.

## Global Constraints

- Preserve `ARROW_DEPENDENCY_SOURCE=BUNDLED` and Arrow shared-library output.
- Do not add bundled third parties to `pkg_deps` or `pkg_build_deps`.
- Do not write under `${OHOS_SDK}` or beside `arrow-cpp/BUILD`.
- Use `.ohloha/downloads/sha256-<URL digest>.archive` through `source_archive_path_for_url` and `with_ohloha_lock`.
- Use pristine upstream archives and preserve Arrow's upstream SHA-256 validation.
- Support `x86_64`, `aarch64`, and `arm` without architecture-specific filesystem paths.
- Do not modify the user's `python3-pyarrow` files.

---

### Task 1: Add Package Policy Regression Check

**Files:**
- Create: `tests/test-arrow-cpp-package.sh`

**Interfaces:**
- Consumes: `arrow-cpp/BUILD` metadata and patch declarations.
- Produces: an executable shell regression check invoked as `bash tests/test-arrow-cpp-package.sh`.

- [ ] **Step 1: Write the failing check**

Create a strict-mode Bash script that fails unless `arrow-cpp/BUILD` uses bundled dependencies, has empty `pkg_deps` and `pkg_build_deps`, declares the 23.0.0 OHOS patch, calls `source_archive_path_for_url` and `with_ohloha_lock`, rejects `thirdparty-cache`, rejects `${OHOS_SDK}` mutation and `|| true` download suppression, and confirms the patch contains both `NOT OHOS` atomic and Boost.Locale conditions.

- [ ] **Step 2: Run the check to verify it fails**

Run: `bash tests/test-arrow-cpp-package.sh`

Expected: non-zero with a message identifying the current `libz` dependency, package-local cache, missing patch, or SDK mutation.

- [ ] **Step 3: Commit the failing check**

```bash
git add tests/test-arrow-cpp-package.sh
git commit -m "test: define arrow-cpp OHOS package policy"
```

### Task 2: Add the OHOS Arrow CMake Patch

**Files:**
- Create: `arrow-cpp/patches/23.0.0/0001-fix-ohos-bundled-boost-and-libatomic.patch`
- Modify: `arrow-cpp/BUILD`

**Interfaces:**
- Consumes: Arrow 23.0.0 `cpp/src/arrow/CMakeLists.txt` and `cpp/cmake_modules/ThirdpartyToolchain.cmake`.
- Produces: `pkg_patch_files` declaration and `prebuilt_patch_once_hook` application through `apply_pkg_patches -p1` from `${current_source_root}`.

- [ ] **Step 1: Generate the source patch**

Create one reviewable patch that:

```cmake
if(${CMAKE_SYSTEM_NAME} STREQUAL "Linux" AND
   ${CMAKE_SYSTEM_PROCESSOR} MATCHES "armv7" AND NOT OHOS)
```

and guards each Boost.Locale include-list/alias operation with `if(NOT OHOS)` while leaving non-OHOS behavior unchanged.

- [ ] **Step 2: Declare and apply the patch**

Add:

```bash
pkg_patch_files="patches/${pkg_version}/0001-fix-ohos-bundled-boost-and-libatomic.patch"
```

and apply it once:

```bash
prebuilt_patch_once_hook() {
    pushd "${current_source_root}"
    apply_pkg_patches -p1
    popd
}
```

Remove the mutable `sed` patching from `prebuilt_patch_hook` and remove the empty `libatomic.a` creation.

- [ ] **Step 3: Verify patch application**

Run `patch --dry-run -p1 -d <clean-arrow-23-source> < arrow-cpp/patches/23.0.0/0001-fix-ohos-bundled-boost-and-libatomic.patch`.

Expected: every hunk succeeds.

### Task 3: Move Bundled Archives into the Repository Cache

**Files:**
- Modify: `arrow-cpp/BUILD`
- Delete: `arrow-cpp/thirdparty-cache/` local generated archives

**Interfaces:**
- Consumes: `source_archive_path_for_url URL`, `with_ohloha_lock LOCK FUNCTION ARGS...`, `sha256_file PATH`.
- Produces: package-local `_cache_arrow_dependency URL EXPECTED_SHA256`, returning the cached absolute archive path on stdout.

- [ ] **Step 1: Implement locked atomic download helper**

Implement `_cache_arrow_dependency` so it derives the repository cache path, downloads with `wget` to `mktemp "${archive}.tmp.XXXXXX"`, validates the expected SHA-256, atomically renames the temporary file, and deletes temporary files on every failure. Existing valid cached archives return immediately; invalid cached archives fail explicitly.

- [ ] **Step 2: Configure pristine bundled archives**

In `custom_build`, call the helper for utf8proc, RapidJSON, RE2, xsimd, LZ4, Zstandard, zlib, Thrift, and Boost using Arrow 23's upstream URLs and checksums. Export their `ARROW_*_URL` variables as `file://` URLs. Do not override `ARROW_BOOST_BUILD_SHA256_CHECKSUM`.

- [ ] **Step 3: Remove stale package-local archives**

Delete `arrow-cpp/thirdparty-cache`. Confirm `git status --short` does not show those generated archives because they were untracked.

- [ ] **Step 4: Run the regression check**

Run: `bash tests/test-arrow-cpp-package.sh`

Expected: PASS.

### Task 4: Verify Metadata and Builds

**Files:**
- Modify: `PKG_INDEX.json` via `./gen-pkg-index.sh`

**Interfaces:**
- Consumes: completed Arrow package changes.
- Produces: syntax-clean metadata and verified OHOS artifacts.

- [ ] **Step 1: Run local static verification**

```bash
bash -n arrow-cpp/BUILD tests/test-arrow-cpp-package.sh
bash tests/test-arrow-cpp-package.sh
OHOS_SDK=/tools/ohos-sdk/18 ./builder.sh --print-meta arrow-cpp/BUILD
./lint-patches.sh --strict
```

Expected: all commands succeed; metadata shows empty dependency arrays and the declared patch.

- [ ] **Step 2: Refresh the package index**

Run: `./gen-pkg-index.sh`

Expected: Arrow 23 metadata has empty `deps`/`build_deps` and contains the new patch path.

- [ ] **Step 3: Build locally for the previously failing target**

Run: `OHOS_SDK=/tools/ohos-sdk/18 ./builder.sh --cpu=x86_64 arrow-cpp/BUILD`

Expected: build succeeds without `unable to find library -latomic`.

- [ ] **Step 4: Inspect the local artifact**

Run `readelf -d` on every installed `libarrow*.so*` and `libparquet*.so*` regular file.

Expected: no `DT_NEEDED` entry for `libatomic`, zlib, zstd, LZ4, RE2, utf8proc, Thrift, or Boost; build logs contain no SDK writes or `arrow-cpp/thirdparty-cache` path.

- [ ] **Step 5: Verify supported architectures on kiwi**

Sync the repository changes to `/home/gjy/Desktop/tmp-robot/`, set `OHOS_SDK=/home/gjy/Desktop/oh_sdk/18` and `PATH=/home/gjy/Desktop/tmp-robot/go/bin:$PATH`, then build Arrow for `aarch64`, `arm`, and `x86_64`. Source `~/ipads-proxy.env` only if downloads fail.

Expected: each supported architecture builds, or any unavailable environmental prerequisite is reported separately from package correctness.

- [ ] **Step 6: Final worktree and diff review**

Run `git diff --check`, `git status --short`, and inspect `git diff -- arrow-cpp tests/test-arrow-cpp-package.sh PKG_INDEX.json`.

Expected: no generated `.ohloha`, `dist*`, or cache files are staged; `python3-pyarrow` user changes remain untouched.
