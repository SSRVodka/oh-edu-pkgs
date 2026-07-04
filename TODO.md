# TODO.md

本文件记录 `ohloha_pkgs` 构建系统的近期目标、阶段性里程碑和可执行验收标准。它面向后续维护者和 Agent：当上下文被压缩、目标不清楚、或准备修改 `builder.sh` / `setup2.sh` / 父目录 Go 项目时，先读本文件和 `DESIGN.md`。

## 总目标

把当前串行、共享工作目录、弱缓存的构建流程，逐步演进为：

- 包构建可重复：同一输入得到同一 artifact，不被上一次构建污染。
- 缓存可信：源码、patch、flags、SDK、工具链、依赖 artifact 不变时跳过重建；任一关键输入变化时自动失效。
- DAG 并发：父目录 Go 项目负责依赖闭包、版本解析、DAG 调度和日志聚合，非祖先关系的节点可并行构建。
- 多版本可用：同名包可以同时存在多个 `BUILD`，依赖约束能解析到具体版本。
- 系统环境干净：不再依赖系统 Python 的全局 `pip install`，不随意写入 OHOS SDK 目录。
- patch 有归属：私有 patch 按包和版本放置，缓存只追踪当前包实际使用的 patch。

## 当前已知问题

- `builder.sh` 把源码缓存和构建工作区都放在 `.staging/<pkg_name>`，导致 `configure`、CMake、Meson、手写 hook 的副作用跨架构、跨 flags 复用。
- `setup2.sh` 固定使用 `.staging` 和 `dist.<cpu>`，`dist.<cpu>` 作为中间安装前缀时不支持并发。
- `setup2.sh` 直接执行 `pip install meson`，在 PEP 668 或受管 Python 环境下会失败。
- `setup2.sh` 可能往 `${OHOS_SDK}` 内写 symlink 或 stub 文件，这不利于并发、缓存和可恢复。
- `builder.sh` 只串行处理传入的 `BUILD` 文件，不解析依赖，也不提供单包 worker 协议。
- 父目录 Go 项目已能做依赖闭包和拓扑排序，但最后仍把所有 `BUILD` 一次性交给 `builder.sh` 串行构建。
- `VERSION` / `VERSIONS` 只以旧文本格式保存有限信息，不保存完整 `BUILD` 路径和构建输入，不适合作为新构建系统的数据源，应以 JSON 包索引和 artifact manifest 替代。
- 根目录 `patches/` 混放包私有 patch，无法精确判断缓存失效范围。

## 里程碑 0：文档和边界确认

目标：让后续改动不偏离整体设计。

任务：

- [x] 新增 `TODO.md` 记录短中期目标。
- [x] 新增 `DESIGN.md` 记录长期架构设计。
- [x] 更新 `AGENTS.md`，提示上下文不明时先读 `TODO.md` 和 `DESIGN.md`。
- [ ] 在每个阶段开始前检查 `git status --short`，记录并避开无关脏文件。
- [ ] 每个阶段建议用独立 git commit 管理，commit 范围只覆盖该阶段目标。

验收：

- 新维护者只读 `AGENTS.md`、`TODO.md`、`DESIGN.md`，可以理解当前方向和阶段边界。

## 里程碑 1：Host 工具环境隔离

目标：去掉系统 Python 和 SDK 目录的隐式写入，为并发和缓存打基础。

任务：

- [x] 新增 `.ohloha/host-venv/` 作为仓库私有 host Python 环境。
- [x] 把 `setup2.sh` 中的 `pip install meson` 改为通过 `.ohloha/host-venv/bin/python3 -m pip` 安装。
- [x] 把 `crossenv` 安装也迁移到 host venv 或明确的私有工具环境。
- [x] 把 `meson`、`ninja`、`crossenv` 等 host 工具路径统一放入 `PATH` 前缀。
- [x] 避免在 `${OHOS_SDK}/native/llvm/bin` 直接创建 `strip`、`profdata` symlink；改用 `.ohloha/tool-wrappers/<sdk-api>/<cpu>/bin`。
- [x] 给 SDK sysroot 中 `libgcc_s.a` stub 的迁移期写入加 lock；后续仍需改为 `.ohloha/sysroot-overlay/<sdk-api>/<cpu>/...`，彻底避免写 SDK。
- [x] 给 host venv 初始化加 lock，避免并发进程同时安装工具。

验收：

- 在不允许系统 `pip install` 的宿主机上，`setup2.sh` 仍能准备 Meson/Python host 工具。
- 执行构建前后，`OHOS_SDK` 目录没有被新增 symlink 或 stub 文件污染，或污染点已被明确 lock 和记录。
- `bash -n setup2.sh builder.sh` 通过。

## 里程碑 2：单包 Worker 协议

目标：让 `builder.sh` 可以被 Go 调度器作为单包构建 worker 调用，同时保留旧串行入口。

任务：

- [x] 新增 `builder.sh --print-meta <BUILD_FILE>`，输出 JSON 元数据。
- [x] 新增 `builder.sh --build-one --cpu=<cpu> <BUILD_FILE>`，只构建一个包。
- [x] 新增 `builder.sh --cache-key --cpu=<cpu> <BUILD_FILE>`，输出构建 fingerprint 或构建输入摘要。
- [x] 保留旧用法 `./builder.sh dep/BUILD foo/BUILD`，内部可串行调用 `build_one`。
- [x] `--print-meta` 输出至少包含 `name`、`version`、`build_file`、`deps`、`build_deps`、`source_url`、`build_type`、`support_archs`。
- [x] 父目录 Go 项目读取 `--print-meta` 或未来的 `PKG_INDEX.json`，废弃四列 `VERSION` 数据源。

验收：

- `./builder.sh --print-meta openssl/BUILD` 输出可被 `jq` 解析的 JSON。
- `./builder.sh --build-one --cpu=aarch64 openssl/BUILD` 行为等价于当前单包构建。
- 旧测试脚本仍可调用旧入口。

## 里程碑 3：目录模型重构

目标：分离下载缓存、源码快照、构建工作区、安装产物和最终输出，消除跨架构/flags 污染。

目标目录结构：

```text
.ohloha/
  downloads/
  sources/
  work/
  artifacts/
  locks/
  logs/
  host-venv/
  tool-wrappers/
  sysroot-overlay/
```

任务：

- [x] 引入 `.ohloha/downloads/<source-key>.archive` 保存原始下载文件。
- [x] 引入 `.ohloha/sources/<source-id>/clean` 保存干净解压源码。
- [x] 引入 `.ohloha/sources/<patched-source-id>/patched` 保存应用包/版本 patch 后的源码快照。
- [ ] 每次 cache miss 从 patched source snapshot 复制、硬链接或 reflink 到 `.ohloha/work/<build-id>/src-root/<pkg_name>`；当前已优先使用 snapshot，缺失 snapshot 时仍 fallback 到 legacy source。
- [x] `current_source_root` 指向 workdir 内源码副本。
- [x] `sources_root` 指向 workdir 内 `src-root`，兼容现有 hook 中以 `${sources_root}` 为 patch 根的写法。
- [x] `target_root_prefix_without_pkgname` 改为 workdir 内的临时安装前缀，不能再共享 `dist.<cpu>`。
- [x] 成功后从 workdir 发布到 legacy `dist.<cpu>.<pkg>`；versioned dist 后续随多版本模型补齐。
- [x] 默认 CMake/Meson build dir 改为绝对 workdir 路径，避免固定污染源码树中的 `ohos-build`；自定义包手写 build dir 后续逐步迁移。
- [x] Meson cross file 从模板生成到 `.ohloha/meson-cross/<api>/<cpu>/pid-<pid>/` 运行时副本，不再并发写 `meson-scripts/*.meson`；默认 Meson 构建继续复制到 workdir 后再注入包级 flags。

验收：

- 先构建 `x86_64`，再构建 `aarch64`，不会复用前者的 `configure`、CMake cache 或 Meson builddir。
- 修改 `CFLAGS` 或包构建 flags 后，自动进入新的 workdir。
- 并发运行两个互不依赖的普通包，不会同时写同一个 `dist.<cpu>` 中间目录。

## 里程碑 4：可信构建缓存

目标：相同输入第二次构建应命中缓存；关键输入变化应自动失效。

任务：

- [x] 定义 `build-id` 计算规则，并让 workdir、`--cache-key` 和 artifact 共享同一 fingerprint 输入。
- [x] artifact manifest 初版记录 `name`、`version`、`arch`、`ohos_api`、`build_id`、`source_sha256`、`build_file_sha256`、`patch_hashes`、`dependency_artifacts` 占位和 toolchain/environment 信息。
- [x] 构建成功后写入 `.ohloha/artifacts/<build-id>/manifest.json`、`payload.tar.zst`、`success`。
- [x] cache hit 时恢复 artifact 到目标 `dist`，不执行 download、patch、configure、make、POSTINST。
- [x] cache hit 前校验 manifest 和 payload 完整性。
- [x] 构建失败不写 `success`，artifact 写入成功后才发布 legacy dist。
- [ ] 新增调试选项；已支持 `--no-cache`、`--force-rebuild`，待补 `--keep-failed-work`。
- [x] `builder.sh --resolved-deps` 支持把已解析依赖 artifact id 写入缓存 key 和 manifest；父目录 Go 侧传入该文件仍待接入。

fingerprint 至少包含：

- 包元数据和所有 `pkg_build_*` 变量。
- `BUILD`、`POSTINST`、实际使用 patch 文件。
- `builder.sh`、`setup2.sh`、`cleanup.sh`、工具链文件和 Meson 模板。
- source URL 和下载归档 sha256。
- `OHOS_CPU`、`OHOS_ARCH`、`OHOS_SDK_API_VERSION`、`OHOS_LIBDIR`。
- 关键工具版本：clang、cmake、meson、python、ninja。
- 最终基础 `CC`、`CXX`、`CFLAGS`、`CXXFLAGS`、`CPPFLAGS`、`LDFLAGS`、`PKG_CONFIG_LIBDIR`。
- resolved dependency artifact ids。

验收：

- 同一包连续构建两次，第二次直接 cache hit。
- 改 `BUILD`、patch、flags、SDK API、目标架构或依赖版本时，cache miss。
- 删除 `.ohloha/work` 不影响 cache hit；删除 `.ohloha/artifacts/<build-id>` 后会重建。

## 里程碑 5：Patch 归属整理

目标：包私有 patch 归属到具体包和版本，缓存只追踪当前包实际使用的 patch。

任务：

- [x] 新增 `pkg_patch_files` 变量或等价机制，允许 BUILD 显式声明 patch 文件。
- [x] 新增 helper：`get_pkg_patch_files`、`apply_pkg_patches`、`apply_pkg_git_patches`。
- [x] 约定私有 patch 放入 `<pkg>/patches/<pkg_version>/`；`pkg_patch_files="patches/${pkg_version}/..."` 相对当前包目录解析。
- [ ] 根目录 `patches/` 只保留真正跨包共享的 patch，或迁移为 `patches/shared/`。
- [ ] 逐步迁移当前根目录私有 patch，例如 `oh-grpc.patch`、`oh-curl.patch`、`oh-openjdk21.0.10+35.patch`。已迁移 `bash`、`boost`。
- [x] 新增 `lint-patches.sh`，检查 patch 引用、归属和废弃全局路径。
- [ ] 缓存 fingerprint 从 hash 整个根 `patches/` 过渡为 hash 当前包声明的 patch 文件。

推荐结构：

```text
boost/
  BUILD
  patches/
    1.81.0/
      0001-ohos-build-config.patch
```

验收：

- 修改 `boost` 私有 patch 只让 `boost` 及其后继依赖失效，不影响无关包。
- 新包不再直接引用 `${PATCH_FILE_ROOT}/oh-<pkg>.patch`。
- 多版本包可以有各自独立 patch 集。

## 里程碑 6：Go DAG 并发调度

目标：父目录 Go 项目负责调度，`builder.sh` 只做单包 worker。

任务：

- [ ] 在父目录 Go 项目中新增 `ohla xcompile --jobs <N>`。
- [ ] 把当前拓扑排序扩展为 ready queue + worker pool。
- [ ] 节点单位从包名逐步迁移为 `PackageID`。
- [ ] worker 调用 `builder.sh --build-one --cpu=<cpu> <BUILD_FILE>`。
- [ ] 每个包日志写入 `.ohloha/logs/<pkg>-<version>-<arch>.log`。
- [ ] 终端输出只打印 concise 状态：pending/running/cache-hit/success/failed/skipped。
- [ ] 节点失败后，将依赖它的后继节点标记为 skipped；`--keep-going` 允许继续构建无关分支。
- [ ] 引入资源锁：download lock、build-id lock、host-venv lock、python/crossenv exclusive lock。

验收：

- 两个无依赖关系的 C/C++ 包可以并行构建。
- 依赖祖先未成功时，后继包不会启动。
- 一个分支失败不会破坏另一个无关分支的构建产物。
- 并发日志可用于定位单包失败原因。

## 里程碑 7：多版本包模型

目标：同名包允许多个版本共存，依赖约束解析到具体版本。

任务：

- [ ] 引入 `PackageID{Name, Version}`。
- [ ] Go 的 `PackageInfo` 增加 `BuildFile`、`SourceURL`、`BuildType`、`SupportArchs`、`PatchFiles`。
- [ ] 新增 `PKG_INDEX.json` 或等价机器可读索引。
- [x] 新增 `gen-pkg-index.sh` 生成 `PKG_INDEX.json`，作为替代 `VERSION` / `VERSIONS` 的机器可读索引入口。
- [ ] 废弃 `gen-versions.sh` / `VERSION` / `VERSIONS` 文本索引，并将 Go 侧和部署脚本迁移到 `PKG_INDEX.json`。
- [ ] 支持目录结构 `pkg/BUILD` 作为默认版本，`pkg/versions/<version>/BUILD` 作为额外版本。
- [ ] 支持用户请求 `openssl`、`openssl==3.0.14`、`openssl>=3,<4`。
- [ ] 依赖解析时选择满足约束的最高版本；冲突时输出明确诊断。
- [ ] `get_pkg_dst_dir <name>` 根据 resolved-deps map 返回具体版本的 dist 路径。
- [ ] 真实输出目录使用 `dist.<cpu>.<name>-<version>`；`dist.<cpu>.<name>` 作为兼容 alias 或当前选择版本。

验收：

- 同一仓库中可以同时存在 `openssl` 两个版本的 `BUILD`。
- 依赖 `openssl<3.1` 的包和依赖 `openssl>=3.5` 的包在冲突时明确报错，或在可隔离场景下解析为不同 PackageID。
- 旧包 hook 中的 `get_pkg_dst_dir openssl` 不需要立即全量改写。

## 里程碑 8：部署和安装链路适配

目标：构建产物、多版本 artifact 和部署工具链保持一致。

任务：

- [x] `pkgs-deploy-all.sh` 支持从 `PKG_INDEX.json` 部署，不再读取 `VERSION` / `VERSIONS`。
- [ ] `pkgs-deploy-all.sh` 进一步改为优先读取 artifact manifest 中的 resolved dependency list。
- [ ] `ohla-tool` 打包时使用 resolved dependency list，而不是仅 `build_deps` 字符串。
- [ ] deploy 文件名包含版本、架构、API，保持与当前 `.pkg/.json` 规则兼容。
- [ ] 安装时可解析同名多版本或至少拒绝冲突。
- [ ] `build_and_install.sh` 使用新的并发 xcompile 入口。

验收：

- `ohla xcompile --jobs N ...` 后可正常 `pkgs-deploy-all.sh`。
- 多版本包不会互相覆盖部署文件。

## 里程碑 9：清理旧模型

目标：在新模型稳定后移除会制造歧义的旧路径和旧逻辑。

任务：

- [ ] 废弃长期复用的 `.staging/<pkg>` 构建模型。
- [ ] 废弃 `.staging.native/`、`.staging.ndst/` 作为 native/host 缓存路径；`native_sources_root`、`native_dst_root` 变量短期作为 hook API 保留，但路径迁移到 `.ohloha/native/`。
- [ ] 废弃 `PATCHED_BY_OHLOHA` 作为源码缓存状态标记。
- [x] 废弃运行时生成并提交风险较高的 `meson-scripts/*.meson`。
- [ ] 废弃私有 patch 放在根目录 `patches/` 的写法。
- [ ] 删除或停止生成 `VERSION` / `VERSIONS` 文本索引，部署脚本改用 `PKG_INDEX.json` / artifact manifest。
- [ ] 明确哪些 legacy 命令继续支持，哪些只保留一段迁移期。

验收：

- 文档、模板、测试脚本都不再推荐旧路径。
- 新增包默认使用新 patch、cache、worker 机制。

## 推荐 Git 管理方式

每个阶段用一个或多个小 commit 管理：

```bash
git status --short
git add TODO.md DESIGN.md AGENTS.md
git commit -m "docs: record build system roadmap"
```

后续实现阶段建议提交格式：

```text
build: isolate host python tools
build: add single package worker mode
build: add artifact cache manifest
pkg: move boost patches under package version
xcompile: schedule build graph concurrently
meta: add package index with build files
```

提交前检查：

- `git status --short`
- `bash -n builder.sh setup2.sh`
- 修改包时额外执行 `bash -n <pkg>/BUILD` 和必要的目标构建。
