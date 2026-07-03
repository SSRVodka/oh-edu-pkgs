# AGENTS.md

本文件给后续 Agent 提供本仓库的项目指引、环境前置和修改规约。适用范围为仓库根目录及其所有子目录。

## 项目定位

`ohloha_pkgs` 是 ohloha 包管理器的 OpenHarmony/鸿蒙原生依赖迁移仓库。每个包目录保存一个源码级交叉编译方案，通常包含：

- `BUILD`：包元数据、源码下载地址、构建类型、依赖、构建 hook。
- `POSTINST`：可选安装后 hook，构建完成后会复制进包输出目录并被执行。
- `patches/`：跨包共享或较大的源码补丁文件。

根目录脚本负责创建包模板、准备交叉编译环境、执行构建、生成版本清单和部署包。`builder.sh` 不解析依赖图，调用者必须按拓扑序传入 `*/BUILD`。

## 环境前置

- 必须设置 `OHOS_SDK`，并且值应指向带 API 版本号的 OpenHarmony SDK 根目录，例如 `.../15`。`setup2.sh` 会读取 `${OHOS_SDK}/toolchains/oh-uni-package.json`。
- 主机依赖见 `DEPS`。可以在合适的容器/系统环境中执行 `source ./DEPS`，但不要在未获用户同意时假设可以修改系统包。
- 构建会下载上游源码，网络不可用时不要把下载失败误判为包脚本错误。
- 默认目标架构为 `aarch64` / `arm64-v8a`。可通过 `builder.sh --cpu=aarch64|arm|x86_64` 指定目标。

## 重要目录和生成物

这些目录/文件主要由构建流程生成或缓存，通常不要手动维护、提交或基于它们推断源码状态：

- `.staging/`：目标源码缓存，源码目录为 `.staging/<pkg_name>`。
- `.staging.native/`、`.staging.ndst/`：native/host 构建缓存和工具输出。
- `dist.<cpu>.<pkg>`：单包目标输出目录，例如 `dist.aarch64.openssl`。
- `dist.<cpu>`：构建中间安装前缀，成功后通常被移动/合并到 `dist.<cpu>.<pkg>`。
- `dist.wheels/`、`crossenv_<cpu>/`、`deploy/`。
- `meson-scripts/*.meson`：由 `setup2.sh` 从 `*.meson.template` 重写生成。
- `VERSION`：由 `./gen-versions.sh` 从各包 `BUILD` 生成；不要手动编辑。

`.gitignore` 已覆盖上述大多数生成物。修改时优先触碰包目录、`patches/`、模板或根目录脚本。

## 常用命令

创建新包模板：

```bash
./pkgs-create.sh foo
```

构建单包：

```bash
./builder.sh foo/BUILD
```

按已知拓扑序构建多个包：

```bash
./builder.sh dep1/BUILD dep2/BUILD foo/BUILD
```

指定架构：

```bash
./builder.sh --cpu=x86_64 foo/BUILD
```

失败后继续构建后续包：

```bash
./builder.sh --continue-on-fail dep1/BUILD dep2/BUILD foo/BUILD
```

运行预设测试构建：

```bash
./test-build-python-and-deps.sh
./test-build-numpy2-and-deps.sh
./test-build-opencv-and-deps.sh
./test-build-ffmpeg-and-deps.sh
./test-build-all.sh
```

生成版本清单：

```bash
./gen-versions.sh
```

部署所有已构建包：

```bash
./pkgs-deploy-all.sh
```

## 包目录规约

新增包时必须使用 `./pkgs-create.sh <pkg>` 从 `.template/` 创建，再修改生成的 `BUILD` 和可选 `POSTINST`。

`BUILD` 文件必须保留模板结构：

- 顶部使用 `#!/bin/bash` 和 `set -Eeuo pipefail`。
- 不要删除、重命名或随意新增模板中的 `pkg_*` 配置变量。
- `setup()` 内填写包元数据；hook 函数放在模板指定位置。
- 保留 `LOAD_NATIVE_HOOK_ONLY` 保护块，`native_env_hook` 依赖它在加载 `setup2.sh` 前运行。

关键字段约束：

- `pkg_version` 必填，格式为版本号，如 `1.2.3`、`1.2`、`1.2.3-rc1`。
- `pkg_name` 必填，不能包含空白；输出目录名和依赖名以它为准。
- `pkg_deps` 和 `pkg_build_deps` 使用英文逗号分隔，不能包含空格，可带 `>=`、`==`、`<` 等版本约束。
- `pkg_source_url` 或 `pkg_release_url` 至少一个非空；下载器期望归档包解压后只有一个顶层目录。
- `pkg_support_archs` 用逗号分隔，可选值包括 `x86_64,aarch64,arm,riscv`。
- `pkg_build_type` 只能是 `autotools`、`cmake`、`meson`、`pure-python`、`custom`。

依赖规则：

- 运行时依赖写入 `pkg_deps`，构建时依赖写入 `pkg_build_deps`。
- `builder.sh` 只会根据 `pkg_build_deps` 为默认构建函数追加 include/lib/pkg-config/CMake 路径；不会自动构建依赖。
- 修改依赖后，检查 `test-deps.sh` 中相关预设拓扑序是否需要同步。

## Hook 规约

`BUILD` hook 中遵守模板注释的硬性约定：

- 不使用相对路径。
- 不使用 `$PWD`、`pwd` 或 `cd`。
- 如需切换目录，使用 `pushd <abs-path>`，并在返回前 `popd`。
- 不在 hook 中创建跨包全局变量；`custom_build` 内可定义局部变量。
- 跨编译相关变量如 `CC`、`CXX`、`CFLAGS`、`LDFLAGS`、`PKG_CONFIG_LIBDIR` 会在包构建后恢复，不要依赖它们泄漏到下一个包。
- hook 内命令失败需要明确处理；脚本启用 `set -Eeuo pipefail`，但条件分支和管道仍需谨慎。

常用 hook 语义：

- `native_env_hook`：在 `setup2.sh` 加载前执行，只能使用 `native_project_root`、`native_sources_root`、`native_dst_root` 等早期变量。
- `custom_download_source`：自定义源码获取。若设置 `_custom_download_source_continue=false`，必须保证源码已放到 `${current_source_root}`。
- `prebuilt_patch_once_hook`：源码目录首次 patch 时执行，完成后会打 `PATCHED_BY_OHLOHA` 标记。
- `prebuilt_patch_hook`：每次构建前执行，适合幂等 patch。
- `custom_build`：自定义或补充构建。设置 `_custom_build_continue=false` 可跳过内置构建流程。
- `post_configure_hook`：内置构建流程完成配置/生成后、真正编译前执行。autotools 中位于 `configure` 后和 `make` 前；CMake 中位于配置命令后和 `cmake --build` 前；Meson 中位于 `meson setup` 后和 `ninja` 前。`pkg_build_type="custom"` 时不会执行；`custom_build` 设置 `_custom_build_continue=false` 跳过默认构建路径时，也不会由默认路径执行。此时可使用 `${current_build_root}` 定位生成的构建目录。
- `postbuilt_hook`：目标输出目录生成后执行，常用于清理、修正或退出临时环境。

补丁建议：

- 简单、稳定的小替换可在 hook 中使用绝对路径 `sed`。
- 较大或可审查性更重要的变更放到 `patches/`，在 `prebuilt_patch_once_hook` 中 `patch --dry-run` 后再应用。

## 构建类型指引

- `cmake`：优先填写 `pkg_build_cmake_extra_cmake_flags` 等字段，让 `build_cmakeproj_with_deps` 处理工具链、安装前缀、依赖路径和 rpath。
- `autotools`：使用 `pkg_build_autotools_*` 字段追加 configure/bootstrap/make-install 设置。
- `meson`：通常设置 `pkg_build_meson_cross_file="${MESON_CROSS_FILE_BASE}"` 或专用模板。需要 Python/meson 环境时，在 `custom_build` 中 `setup_pycrossenv`，在 `postbuilt_hook` 中 `destroy_pycrossenv || true`。
- `pure-python`：只适合无 native 包依赖的 Python 包；通常需要 `pkg_build_deps` 包含 `python3,python3-build,python3-wheel,python3-setuptools`。
- `custom`：仅在内置流程不适合时使用。自定义流程必须安装到 `${target_root_with_pkgname}`，并设置 `_custom_build_continue=false`。

不要重复实现根脚本已处理的通用逻辑：依赖 include/lib/pkg-config 路径、CMake prefix/find-root、安装前缀、`.pc`/`.la` 修正和共享库 rpath 修正优先交给 `setup2.sh` 中的 helper。

## POSTINST 规约

`POSTINST` 可选。存在时 `builder.sh` 会：

1. 复制它到 `${target_root_with_pkgname}`。
2. 以 `${target_root_with_pkgname}` 作为第一个参数执行。
3. 忽略执行失败继续后续流程。

推荐模板：

```bash
#!/bin/bash
set -Eeuo pipefail

_prefix=${1:-}
if [ -z "$_prefix" ]; then
    echo "ERROR: empty prefix in 1st parameter"
    exit 1
fi
```

## 版本和清单

- `VERSION` 是生成物，运行 `./gen-versions.sh` 后会从每个一级包目录的 `BUILD` 抽取 `pkg_name`、`pkg_version`、`pkg_deps`、`pkg_build_deps`。
- `VERSIONS` 是已有静态参考清单；除非任务明确要求维护它，否则不要用它替代 `BUILD` 内的真实元数据。
- 打包部署使用 `VERSION` 和 `dist.<cpu>.<pkg>`。

## 修改和验证流程

修改包脚本时建议按以下顺序工作：

1. 阅读目标包 `BUILD`、相关 `POSTINST`、上游构建系统和相邻同类包写法。
2. 确认依赖是否已在仓库中存在；缺失依赖需先迁移或明确说明。
3. 选择最接近上游构建系统的 `pkg_build_type`。
4. 优先使用 `pkg_build_*` 字段和 helper；只在必要时写 hook。
5. 若新增包或修改依赖，检查 `test-deps.sh`。
6. 能构建时至少运行目标包及其依赖的 `./builder.sh ...`；无法构建时说明缺失的环境、网络或 SDK 条件。
7. 如需刷新包清单，运行 `./gen-versions.sh`，但不要手工编辑 `VERSION`。

提交前检查：

- `git status --short`，确认没有把 `.staging*`、`dist*`、`crossenv_*`、`deploy/`、`meson-scripts/*.meson` 等生成物纳入提交。
- `bash -n <pkg>/BUILD` 和 `bash -n <pkg>/POSTINST` 可作为快速语法检查。
- 不要回滚用户已有修改；遇到无关脏文件只记录并避开。
