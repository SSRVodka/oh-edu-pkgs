## ohloha pkgs

ohloha 包管理器的包迁移仓库，存放着各种系统依赖库的编译构建和安装时补丁的流程。

本仓库提供了从源码级别的成体系的迁移方案，您可以在此基础上很轻松的迁移其他需要的库。

通过 [`ohloha`](https://gitcode.com/openharmony-robot/tools_ohloha) ([gh mirror](https://github.com/SSRVodka/oh-packager)) 支持并发编译、缓存等能力。

AI 友好：提供了 `AGENTS.md`, `DESIGN.md` 文档，以及迁移包的 skill（位于 `.agents/skills` 下，对于 codex 也可使用 `cp -r .agents/skills/* ~/.codex/skills/` 安装）。

### 进度


- [x] 80+ 系统依赖库：如 openblas, binutils, zstd, curl, ...

- [x] Python 解释器，及常见 native 库：libaacplus、x264、alsa-lib、ffmpeg、bzip2、gettext、libffi、ncurses、OpenBLAS、openssl、readline、sqlite3、xz、zlib；

- [x] Python 第三方库：numpy、scipy、opencv、onnxruntime、openai；

- [ ] ...

- [ ] 如果您有需要构建的第三方库 / 有构建的思路和方法，欢迎提 issue / PR，共同建设。

### 准备

1. 首先需要设置环境变量 OHOS_SDK（建议写入 .bashrc/.zshrc）为你的 OpenHarmony SDK 的根目录。请注意，它需要包含 API 版本号，例如 [...]/15；

2. 您需要安装 [`DEPS`](./DEPS) 中指定的包来为构建做准备。如果您不想看安装了什么包，可以直接执行 `source ./DEPS`；

### 测试

如果您想要测试该补丁框架能否正确编译，暂时不想使用 ohloha 管理，您可以使用本仓库的 `test-build-*.sh` 系列脚本。执行这些脚本（任意一个）后会开始按预设的顺序依次编译。例如 `test-build-opencv-and-deps.sh` 会按顺序编译 opencv 和所需的依赖库并输出到 `dist.<arch>.<pkg>-<version>`；

### 添加 (向 OH 迁移) 新的库

请使用 `./pkgs-create.sh` 从模板创建一个迁移工具。举例：

```shell
./pkgs-create.sh foo
# 多个包这么创建：
# ./pkgs-create.sh foo bar bazz
```

现在就成功创建了一个 foo 包，你需要按照 `foo/BUILD` 中的指示填写关键信息，包括版本、依赖、构建 hooks、以及 `foo/POSTINST` 安装时 hook 脚本。

填写完成后执行 `./builder.sh foo/BUILD` 构建这个包。成功后会输出到 `dist.<arch>.foo-<version>` 目录下。构建器不再自动创建 `dist.<arch>.foo` legacy alias；如外部脚本确实需要这个名字，可以自行创建软链接。

注意，`builder.sh` 本身不会管理依赖图，`ohloha` [包管理器](https://gitcode.com/openharmony-robot/tools_ohloha) 会管理并生成指令调用 `builder.sh` 构建这些包。

您在测试时可以按照依赖关系这样依次构建（按拓扑序方向从前到后）：`./builder.sh dep1/BUILD dep2/BUILD dep3/BUILD foo/BUILD`。同一个 builder 进程会记住前面成功发布的版本化 dist 路径，后续包的 `get_pkg_dst_dir <dep>` 会使用这些路径。

如果只单独执行 `./builder.sh foo/BUILD`，即使仓库里已经存在 `dist.<arch>.<dep>-<version>`，构建器也不会扫描已有 dist 并自动猜测依赖版本。需要单独构建依赖型包时，请使用 `--resolved-deps` 明确传入依赖路径，或仍按拓扑序把依赖 BUILD 一起传入。这是为了避免同名多版本包被隐式选错。

> [!TIP]
>
> FAQ：如何确定一个库的 `pkg_deps / pkg_build_deps`？
>
> 这个工作其实应该由编写这个库的开发者决定的，因此您在迁移时需要到被迁移库的源码仓库里自行查找依赖。一般会文档里（例如 build from source 的文档）。假设想要迁移库 A，整体流程如下：
>
> 1. 到 A 的源码仓库 / 文档查找 A 的编译时、运行时依赖，假设都是 B、C、D；
> 2. 依次检查 B、C、D 是否已经被迁移完成（已经存在 `ohloha_pkgs` 里面了）；
>    - 如果是，直接在 `pkg_deps / pkg_build_deps` 里面添加即可；
>    - 如果否，需要您递归地迁移这些依赖（对 B/C/D 从第一步开始迁移）；
> 3. 填写完 `pkg_deps` 和 `pkg_build_deps` 后，您应该先用 `builder.sh` 测试构建能否成功（依赖自行管理，如 `./builder.sh B/BUILD C/BUILD D/BUILD A/BUILD`），如果有问题则调整相应的 flags 和选项，直至编译成功，方可提交 PR；

> [!TIP]
>
> FAQ：如何确定一个库的 `pkg_build_type`？
>
> 同样由编写这个库的开发者决定的，这主要是因为目前 C/C++ 库的构建工具繁多但不统一导致的。
>
> 举个例子，您应该到被迁移的库的源码仓中检查，如果它的编译工具支持 `cmake`（文档里说可以这么编译，或者包含 `CMakeLists.txt`），那么就是 `cmake` 类型；如果源码仓使用 `configure` 和 `Makefile`，那么就是 `autotools` 类型；如果源码仓使用 `meson.build`，那么就是 `meson` 类型，依此类推。
>
> 对于不同的 `pkg_build_type`，`builder.sh` 内置了不同的交叉编译构建流程，对于一般的库，方便您不需要设置一些交叉编译的繁琐 flags 就能直接使用。内置默认逻辑如下：
>
> 首先执行 hook `custom_build`，如果用户最后设置了 `_custom_build_continue=false`，那么直接结束构建。否则执行下面的逻辑：
>
> - `cmake` 构建类型的库：自动按照依赖关系设置 `CMAKE_PREFIX_PATH / CMAKE_FIND_ROOT_PATH`、C/C++/LD flags、`PKG_CONFIG_DIR` 等等，并使用 `ohos.toolchain.xhw.cmake` 工具链定义开始构建；
>
> - `autotools` 构建类型的库：自动按照依赖关系为 `configure` 设置 `--prefix / --host / --target / --build / --libdir` 等参数、C/C++/LD flags、各种 compilers 环境变量、`PKG_CONFIG_DIR` 等等，并使用 `make` 构建和安装；
>
> - `meson` 构建类型的库：自动设置 meson 交叉工具链模板文件 `meson-scripts/*`，并使用 host 上的 `meson` 启动构建；
>
>   你需要使用时手动指定 `pkg_build_meson_cross_file` 为修改后的 `*.meson` 文件，例如 `${MESON_CROSS_FILE_BASE}`；
>
> - `pure-python` 构建类型的库：进入预先准备的 `crossenv`，从源码构建 wheel，并将 wheel 安装到目标 Python 包目录；
>
> - `pyo3-rust` 构建类型的库：进入或复用 Python `crossenv`，设置 PyO3/Rust/Cargo/cc-rs 交叉编译变量，并通过仓库私有 host tool `${HOST_MATURIN}` 构建 maturin wheel；
>
> - `custom` 构建类型的库：不做任何处理；
>
> 如果您希望彻底从头定制构建流程、管理依赖等等，或者有些库的编译流程，不希望依赖 `builder.sh` 内部的构建逻辑，您可以使用 `custom` 构建类型，并且在 `BUILD` 文件的 `custom_build` 函数中进行自定义流程。更多要求请参见 `.template/BUILD` 中的注释内容。
>
> 最后，如果您还是不知如何编写，可以参考本仓库里典型的案例的写法。例如：
>
> - `meson` 类型：`libdrm/BUILD`、`mesa/BUILD` 等；
> - `custom` 类型：`boost/BUILD`、`xorg/BUILD` 等；
> - `cmake` 类型：`grpc/BUILD`、`zstd/BUILD` 等；
> - `autotools` 类型：`util-linux/BUILD`、`libncursesw/BUILD` 等；
> - `pure-python` 类型：`python3-build`、`python3-setuptools` 等；
> - `pyo3-rust` 类型：`python3-tokenizers`、`python3-safetensors` 等。

#### 非 Rust native Python 包

包含 C/C++ 扩展、但不涉及 Rust/PyO3 的 Python 包，通常使用 `pkg_build_type="custom"`，因为 setuptools、Cython、Meson、scikit-build、SWIG 等后端的依赖参数差异较大。推荐流程为：

1. `setup_pycrossenv`：进入交叉 Python 环境，并设置目标 Python/NumPy 的基础编译和链接参数；
2. 在 `custom_build` 中解析 native 依赖路径，追加包专用的 `CFLAGS`、`LDFLAGS`、pkg-config、CMake 或后端变量；
3. 如需 `--no-build-isolation`，先使用 `${PYCROSS_BUILD_PIP}` 安装全部 PEP 517 backend/plugin；仅安装到 `${HOST_TOOLS_PYTHON}` 无效；
4. 调用 `build_python_cross_package_active -v --no-deps --no-binary :all: ...` 从源码生成 wheel；
5. 无论构建成功还是失败，都调用 `destroy_pycrossenv` 退出环境并释放锁；
6. 在 `postbuilt_hook` 中调用 `install_current_python_wheelhouse_to_target_site_packages`，把当前 wheelhouse 安装到包输出目录。

应优先复用现有 helper，不要在单个 `BUILD` 中重复实现 wheel 目录管理、归档或安装逻辑。如果进入 crossenv 后不需要额外准备，可直接使用 `build_python_cross_package ...`；它已经封装 `setup_pycrossenv`、active build 和 cleanup，不要再在外层重复进入 crossenv。

交叉编译完成后，禁止在包 hook 中显式使用 `${PYCROSS_CROSS_PIP}` 把新生成的包安装回共享 crossenv，例如不要执行 `${PYCROSS_CROSS_PIP} install --force-reinstall --no-deps --no-index --find-links "$wheel_dir" "xxx==${pkg_version}"`。这会把当前包状态泄漏给后续构建。最终包只能通过 `postbuilt_hook` 中的 `install_current_python_wheelhouse_to_target_site_packages` 安装到 `${target_root_with_pkgname}`。完整模板和注意事项见 `.agents/skills/ohloha-package-migration/references/package-categories.md`。

### 编译时注意事项

如需配置编译目标架构，调用 `builder.sh` 时指定 `--cpu` 参数（可选 `aarch64/arm/x86_64`）即可，或者请参考注释修改 `setup2.sh` 的 `OHOS_CPU` 和 `OHOS_ARCH` 定义；

编写 `BUILD` 时，`setup()` 应只填写静态元数据和不依赖构建现场的默认值。不要在 `setup()` 中调用 `get_pkg_dst_dir`，也不要读取 `HOST_PYTHON_DIST`、`NUMPY*_LIBROOT`、`target_root_*`、`CFLAGS/LDFLAGS` 等运行态变量来拼动态 flags。依赖路径、Python/numpy include/lib 路径、根据当前 arch/workdir 计算出的 CMake/autotools/meson flags，应放在 `custom_build`、`post_configure_hook` 等 build 阶段 hook 中设置。

#### Python 构建环境

Python crossenv 运行目录由 `setup2.sh` 管理在 `.ohloha/crossenv/<sdk-api>/<cpu>/`。BUILD 中如需引用交叉 Python 环境，应使用 `PY_CROSS_ROOT`、`HOST_SITE_PKGS`、`PYCROSS_CROSS_PYTHON`、`PYCROSS_CROSS_PIP`、`PYCROSS_BUILD_PIP`、`PYPKG_OUTPUT_WHEEL_DIR` 等变量，不要硬编码旧的 `crossenv_<cpu>` 路径。通用 Python helper 会先构建 wheel，归档到 `dist.wheels/`，再从本地 wheel 安装到 crossenv。CPython 交叉编译所需的 build-python 位于 `.ohloha/native/build-python`，根目录旧 `build-python.dist` 仅视为 legacy 生成物。

Python 包构建时不要轻易给 `build_python_cross_package` 加 `--no-build-isolation`。`HOST_TOOLS_PYTHON` 是仓库私有 host tools venv，`build_python_cross_package` 实际进入的是 Python crossenv；PEP 517 build backend 会在 crossenv 的构建环境中导入。因此只把 `hatchling`、`flit_core`、`setuptools_scm` 等 backend 装进 `HOST_TOOLS_PYTHON`，不能满足 `--no-build-isolation` 构建。通常应保留 build isolation，让 `pip wheel` 按 `pyproject.toml` 自动安装 `[build-system].requires`；需要避免拉运行时依赖时使用 `--no-deps`，不要用 `--no-build-isolation`。只有确实需要复用已准备的 build-side Python 包时，才在 `setup_pycrossenv` 之后显式安装到 `${PYCROSS_BUILD_PIP}`，再使用 `build_python_cross_package_active ... --no-build-isolation`。

PyO3/Rust 包不要在 `BUILD` 中修改 `PATH`、执行 `rustup target add` 或 `pip install maturin`。Rust 工具链和 target 是宿主环境前置；`maturin` 由 `.ohloha/host-venv/` 管理，通用 `pyo3-rust` 构建类型会使用明确的 `${HOST_MATURIN}`、`${HOST_TOOLS_PYTHON}` 和 Python crossenv 路径。
