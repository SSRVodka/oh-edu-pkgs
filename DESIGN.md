# DESIGN.md

本文件记录 `ohloha_pkgs` 未来构建系统的长期设计。它不是当前实现的完整说明，而是后续重构时应遵守的架构边界、数据模型和兼容策略。具体阶段安排见 `TODO.md`。

## 设计原则

1. 构建输入必须可描述。
   缓存是否命中应由明确 fingerprint 决定，而不是靠目录是否存在。

2. 源码缓存和构建工作区必须分离。
   上游源码、应用 patch 后的源码快照、configure/CMake/Meson 生成物、安装产物不能混在同一个长期复用目录里。

3. `builder.sh` 是单包 worker，不是全局调度器。
   依赖解析、版本选择、DAG 并发和失败传播应由父目录 Go 项目负责。

4. `BUILD` hook 兼容优先。
   现有包大量依赖 Bash hook，重构时要保留 `current_source_root`、`sources_root`、`target_root_with_pkgname` 等变量语义，但可以把它们指向新的隔离 workdir。

5. 私有 patch 属于包和版本。
   只有真正跨包共享的 patch 才允许放在共享目录。缓存应只追踪当前包实际使用的 patch。

6. Host 工具链不污染系统。
   Meson、crossenv、Python build helpers 等应放入仓库私有工具环境。构建脚本不应要求系统环境允许全局 `pip install`。

7. SDK 目录应尽量只读。
   构建期 wrapper、symlink、stub 和 overlay 应放在 `.ohloha/` 下，再通过 `PATH`、flags 或 sysroot overlay 注入。

8. 并发必须建立在隔离和锁之上。
   没有独立 workdir、独立安装前缀、独立 Meson cross file 和 artifact lock 时，不应直接并发运行旧 `builder.sh` 多包流程。

## 项目边界

`ohloha_pkgs` 负责：

- 保存包迁移定义：`BUILD`、`POSTINST`、包私有 patch。
- 提供单包构建 worker：下载、准备源码快照、执行 hook、调用构建系统、生成 artifact。
- 提供包元数据导出入口：例如 `builder.sh --print-meta` 或 `PKG_INDEX.json` 生成脚本。新系统不再以 `VERSION` / `VERSIONS` 文本文件作为权威数据源。
- 提供 legacy 兼容入口：旧的 `./builder.sh dep/BUILD foo/BUILD` 可继续串行工作。

父目录 Go 项目负责：

- 读取包索引。
- 解析版本约束。
- 选择具体 `PackageID`。
- 生成依赖闭包和 DAG。
- 并发调度 `builder.sh --build-one`。
- 聚合日志和失败状态。
- 调用打包、部署和安装链路。

不应由 `builder.sh` 负责：

- 自动求依赖闭包。
- 跨包 DAG 并发。
- 多版本约束求解。
- 全局安装已构建包。

## 目标目录模型

未来所有可丢弃、可缓存、可恢复的构建状态统一放入 `.ohloha/`：

```text
.ohloha/
  downloads/
    <source-key>.archive
  sources/
    <source-id>/clean/
    <patched-source-id>/patched/
  work/
    <build-id>/
      src-root/<pkg_name>/
      build/
      install/
      meson/
      env.json
  artifacts/
    <build-id>/
      manifest.json
      payload.tar.zst
      success
  locks/
  logs/
  host-venv/
  tool-wrappers/
  sysroot-overlay/
```

现有 legacy 目录在迁移期只作为旧产物识别，不作为新设计目标：

- `.staging/`
- `.staging.native/`
- `.staging.ndst/`
- `dist.<cpu>.<pkg>`
- `dist.<cpu>`
- `dist.wheels/`
- `crossenv_<cpu>/`
- `meson-scripts/*.meson`

最终目标是让 `.staging/<pkg>` 不再作为长期复用的构建工作区；`.staging.native/` 和 `.staging.ndst/` 也不再作为 native/host 缓存路径。`native_sources_root`、`native_dst_root` 变量可短期保留给旧 hook 使用，但应指向 `.ohloha/native/sources` 和 `.ohloha/native/dst`。

## 构建生命周期

单包构建的目标流程：

1. 读取 `BUILD`，执行 `setup()`，导出元数据。
2. 解析 target：`OHOS_CPU`、`OHOS_ARCH`、`OHOS_SDK_API_VERSION`、工具链路径。
3. 解析依赖：由 Go 侧传入 resolved dependency map。
4. 计算 source key：source URL、自定义下载声明、归档 sha256。
5. 下载归档到 `.ohloha/downloads/`，用 lock 防止重复下载。
6. 解压干净源码到 `.ohloha/sources/<source-id>/clean/`。
7. 应用包/版本 patch，生成 `.ohloha/sources/<patched-source-id>/patched/`。
8. 计算 build-id。
9. 如果 artifact 命中并校验通过，恢复到目标 dist，构建结束。
10. cache miss 时创建 `.ohloha/work/<build-id>/`。
11. 从 patched source snapshot 复制源码到 workdir。
12. 设置 hook 变量，让现有 `BUILD` hook 只看到隔离后的 workdir 路径。
13. 执行 `custom_build` 或默认 autotools/CMake/Meson/pure-python 构建。
14. 执行 `postbuilt_hook` 和 `POSTINST`。
15. 校验安装目录，打包为 artifact payload。
16. 原子写入 artifact manifest 和 `success`。
17. 原子发布到 legacy 或 versioned dist 目录。
18. 按策略保留或删除 workdir。

失败时：

- 不写 `success`。
- 不发布半成品 dist。
- 默认可删除 workdir；使用 `--keep-failed-work` 时保留。
- 日志必须保留在 `.ohloha/logs/`。

## Hook 变量兼容

现有包仍可使用这些变量，但其路径语义会迁移到隔离 workdir：

```bash
current_source_root=.ohloha/work/<build-id>/src-root/<pkg_name>
sources_root=.ohloha/work/<build-id>/src-root
current_build_root=.ohloha/work/<build-id>/build 或构建系统生成目录
target_root_prefix_without_pkgname=.ohloha/work/<build-id>/install/dist.<cpu>
target_root_with_pkgname=.ohloha/work/<build-id>/install/dist.<cpu>.<pkg>
```

`get_pkg_dst_dir <dep>` 不应直接拼 `dist.<cpu>.<dep>`。未来应优先查 resolved dependency map：

```json
{
  "libz": "/repo/dist.aarch64.libz-1.3.1",
  "openssl": "/repo/dist.aarch64.openssl-3.5.0"
}
```

没有 resolved map 时，可 fallback 到 legacy 路径，保持旧脚本可用。

## Native/Host 构建变量

`native_project_root`、`native_sources_root`、`native_dst_root` 目前被多个 `native_env_hook` 和自定义构建脚本使用。它们的长期定位不同：

- `native_project_root` 保留，语义是仓库根目录。它适合引用仓库内脚本、共享 patch、临时兼容资源，但不应被用作包构建缓存目录。
- `native_sources_root` 短期保留为 hook API，但路径应指向 `.ohloha/native/sources`，不再指向 `.staging.native`。
- `native_dst_root` 短期保留为 hook API，但路径应指向 `.ohloha/native/dst`，不再指向 `.staging.ndst`。

未来可以新增更清晰的别名，例如 `project_root`、`host_sources_root`、`host_tools_root`，再逐步迁移包脚本。迁移完成前，不要删除旧变量名；但也不要把它们理解为旧 `.staging.*` 设计需要继续保留。

## 单包 Worker 接口

目标接口：

```bash
./builder.sh --print-meta <BUILD_FILE>
./builder.sh --cache-key --cpu=aarch64 <BUILD_FILE>
./builder.sh --build-one --cpu=aarch64 <BUILD_FILE>
```

旧接口保留：

```bash
./builder.sh --cpu=aarch64 dep/BUILD foo/BUILD
```

`--print-meta` 输出 JSON：

```json
{
  "name": "openssl",
  "version": "3.5.0",
  "build_file": "openssl/BUILD",
  "deps": ["libz>=1.0"],
  "build_deps": ["libz>=1.0"],
  "source_url": "https://example.invalid/openssl.zip",
  "release_url": "",
  "license": "Apache-2.0",
  "support_archs": ["x86_64", "aarch64", "arm"],
  "build_type": "autotools",
  "patch_files": []
}
```

`PKG_INDEX.json` 是由 `gen-pkg-index.sh` 聚合 `--print-meta` 结果生成的 JSON 数组。它替代旧的 `VERSION` / `VERSIONS` 文本清单，供 Go 侧 xcompile、部署脚本和后续工具读取。该文件是生成物，不应手工维护。

`--build-one` 可接受额外参数：

```bash
--resolved-deps=/path/to/resolved-deps.json
--cache-dir=/path/to/.ohloha
--no-cache
--force-rebuild
--keep-failed-work
--log-file=/path/to/log
```

## Artifact Manifest

artifact manifest 是缓存可信的依据。建议格式：

```json
{
  "format": 1,
  "name": "openssl",
  "version": "3.5.0",
  "arch": "aarch64",
  "ohos_api": "18",
  "build_id": "sha256:...",
  "source_sha256": "...",
  "build_file_sha256": "...",
  "postinst_sha256": "...",
  "patch_hashes": {
    "openssl/patches/3.5.0/0001-ohos.patch": "sha256:..."
  },
  "scripts": {
    "builder.sh": "sha256:...",
    "setup2.sh": "sha256:...",
    "cmake/ohos.toolchain.xhw.cmake": "sha256:..."
  },
  "toolchain": {
    "ohos_sdk": "/path/to/sdk/18",
    "ohos_api": "18",
    "clang_version": "...",
    "cmake_version": "...",
    "meson_version": "...",
    "python_version": "..."
  },
  "environment": {
    "OHOS_CPU": "aarch64",
    "OHOS_ARCH": "arm64-v8a",
    "OHOS_LIBDIR": "lib",
    "CFLAGS": "...",
    "LDFLAGS": "..."
  },
  "dependency_artifacts": {
    "libz": "sha256:..."
  },
  "payload": "payload.tar.zst",
  "payload_sha256": "...",
  "created_at": "2026-07-03T00:00:00Z"
}
```

cache hit 必须满足：

- manifest 存在。
- `success` 存在。
- payload 存在且 sha256 匹配。
- 当前计算出的 build-id 与 manifest 中一致。

## Fingerprint 规则

`build-id` 必须覆盖会影响构建结果的输入：

- 包元数据和所有 `pkg_build_*` 变量。
- `BUILD` 文件 hash。
- `POSTINST` 文件 hash。
- 当前包实际使用的 patch 文件 hash。
- `builder.sh`、`setup2.sh`、`cleanup.sh`、toolchain file、Meson template hash。
- source URL、release URL、自定义下载身份、归档 sha256。
- `OHOS_CPU`、`OHOS_ARCH`、`OHOS_SDK_API_VERSION`、`OHOS_LIBDIR`。
- clang、cmake、meson、ninja、python、pip 等关键工具版本。
- 基础编译环境：`CC`、`CXX`、`CFLAGS`、`CXXFLAGS`、`CPPFLAGS`、`LDFLAGS`、`PKG_CONFIG_LIBDIR`。
- resolved dependency artifact ids。

不应包含：

- 临时 workdir 绝对路径，除非路径被写进最终产物且无法消除。
- 日志路径。
- 并发 worker 编号。
- 纯调试选项，例如 `--keep-failed-work`。

## Patch 归属设计

根目录 `patches/` 的旧模式只适合迁移期。目标模式：

```text
<pkg>/
  BUILD
  POSTINST
  patches/
    <pkg_version>/
      0001-ohos-cross-build.patch
      0002-fix-configure-cache.patch
```

多版本包可使用：

```text
<pkg>/
  BUILD
  patches/<current-version>/
  versions/
    <version>/
      BUILD
      patches/
        0001-ohos.patch
```

`BUILD` 可显式声明。这里的 `patches/${pkg_version}/...` 是相对当前包目录解析，例如
`boost/BUILD` 中的声明会指向 `boost/patches/1.81.0/...`，不是仓库根目录
`patches/1.81.0/...`：

```bash
pkg_patch_files="patches/${pkg_version}/0001-ohos-cross-build.patch"
```

helper：

```bash
apply_pkg_patches -p1
apply_pkg_git_patches
```

迁移期兼容：

- `PATCH_FILE_ROOT` 保留。
- 旧包仍可引用根目录 patch。
- 缓存层遇到旧全局 patch 引用时保守处理。

最终目标：

- 私有 patch 不放根目录。
- 缓存只 hash 当前包声明或自动发现的 patch。
- 修改一个包的 patch 不让无关包缓存失效。

## 多版本模型

未来包节点不是单纯的包名，而是：

```go
type PackageID struct {
    Name    string
    Version string
}
```

包索引模型：

```go
type PackageInfo struct {
    Name         string
    Version      string
    BuildFile    string
    Depends      []string
    BuildDepends []string
    SourceURL    string
    ReleaseURL   string
    BuildType    string
    SupportArchs []string
    PatchFiles   []string
}
```

版本选择规则：

- 用户请求 `openssl`：选择满足隐含约束的最新版本。
- 用户请求 `openssl==3.0.14`：选择精确版本。
- 依赖 `openssl>=3,<4`：选择满足范围的最高版本。
- 同一闭包出现不可满足约束时，输出冲突链路。

输出目录：

```text
dist.<cpu>.<name>-<version>   # canonical
dist.<cpu>.<name>             # legacy alias/current selected version
```

legacy alias 可以是 symlink，也可以是 copy/atomic rename。为了兼容部署脚本，迁移初期建议继续生成真实目录。

## Go DAG 调度设计

Go 调度器负责：

1. 读取 `PKG_INDEX.json` 或调用 `builder.sh --print-meta` 生成索引。
2. 解析用户请求和依赖约束。
3. 得到 `PackageID` 闭包。
4. 构建 DAG。
5. 使用 ready queue 和 worker pool 并发构建。
6. 节点成功后释放后继节点。
7. 节点失败后标记后继为 skipped。
8. 输出状态摘要和日志路径。

worker 命令：

```bash
builder.sh --build-one \
  --cpu=aarch64 \
  --resolved-deps=/tmp/ohloha/<pkg-id>.deps.json \
  --log-file=.ohloha/logs/<pkg-id>.log \
  <BUILD_FILE>
```

并发安全资源：

- `download:<source-key>`
- `build:<build-id>`
- `host-venv`
- `native-tool:<name>`
- `python-crossenv:<cpu>`
- `dist-publish:<name/version/arch>`

普通 C/C++ 包可并发；修改共享 Python/crossenv/native host tool 的包应先用资源锁串行化。

## 兼容策略

迁移期间必须兼容：

- 现有 `BUILD` 模板变量。
- 现有 hook 名称。
- 旧 `./builder.sh <BUILD>...` 调用方式。
- 旧 `dist.<cpu>.<pkg>` 输出目录。

允许新增但不要立即强制：

- `pkg_patch_files`
- `PKG_INDEX.json`
- `dist.<cpu>.<pkg>-<version>`
- `.ohloha/` 缓存目录
- `builder.sh --build-one`
- `ohla xcompile --jobs`

不需要为新设计保留兼容：

- `VERSION` / `VERSIONS` 文本索引格式。
- 依赖 `VERSION` 列位置的部署和 xcompile 逻辑。
- `.staging.native/` / `.staging.ndst/` 作为 native/host 缓存路径。

废弃应分阶段完成：

1. 文档标记 deprecated。
2. lint warning。
3. 新包禁止使用。
4. 旧包迁移后改为 error。

## 维护注意事项

- 不要在没有隔离 workdir 的情况下给现有多包 `builder.sh` 加并发。
- 不要把 `.staging/<pkg>` 是否存在当作构建成功或缓存命中的依据。
- 不要让不同包并发写同一个 `dist.<cpu>` 中间目录。
- 不要让不同包并发写同一个 `meson-scripts/*.meson`。
- 不要把整个根 `patches/` 永久纳入所有包的 cache key；这只能作为迁移期保守 fallback。
- 不要继续扩展 `VERSION` / `VERSIONS`；未来也不要手工编辑机器生成的 `PKG_INDEX.json`。
- 修改构建脚本后优先做语法检查，再做小包构建验证。

## 推荐验证层级

轻量检查：

```bash
bash -n builder.sh setup2.sh
bash -n <pkg>/BUILD
git status --short
```

单包检查：

```bash
./builder.sh --cpu=aarch64 <pkg>/BUILD
```

缓存检查：

```bash
./builder.sh --build-one --cpu=aarch64 <pkg>/BUILD
./builder.sh --build-one --cpu=aarch64 <pkg>/BUILD
```

并发检查：

```bash
ohla xcompile --arch aarch64 --jobs 4 <pkg1> <pkg2>
```

多版本检查：

```bash
ohla xcompile --arch aarch64 'openssl==3.0.14'
ohla xcompile --arch aarch64 'openssl>=3.5,<4'
```

这些命令会随实现进度逐步可用；在对应里程碑未完成前，不要把未实现命令当作当前验证要求。
