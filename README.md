## ohloha pkgs

ohloha 包管理器的包迁移仓库，存放着各种系统依赖库的编译构建和安装时补丁的流程。

本仓库提供了从源码级别的成体系的迁移方案，您可以在此基础上很轻松的迁移其他需要的库。

### 进度


- [x] 80+ 系统依赖库：如 openblas, binutils, zstd, curl, ...

- [x] Python 解释器，及常见 native 库：libaacplus、x264、alsa-lib、ffmpeg、bzip2、gettext、libffi、ncurses、OpenBLAS、openssl、readline、sqlite3、xz、zlib；

- [x] Python 第三方库：numpy、scipy、opencv、onnxruntime；

- [ ] ...

- [ ] 如果您有需要构建的第三方库 / 有构建的思路和方法，欢迎提 issue / PR，共同建设。

### 准备

1. 首先需要设置环境变量 OHOS_SDK（建议写入 .bashrc/.zshrc）为你的 OpenHarmony SDK 的根目录。请注意，它需要包含 API 版本号，例如 [...]/15；

2. 您需要安装 [`DEPS`](./DEPS) 中指定的包来为构建做准备。如果您不想看安装了什么包，可以直接执行 `source ./DEPS`；

### 测试

如果您想要测试该补丁框架能否正确编译，暂时不想使用 ohloha 管理，您可以使用本仓库的 `test-build-*.sh` 系列脚本。执行这些脚本（任意一个）后会开始按预设的顺序依次编译。例如 `test-build-opencv-and-deps.sh` 会按顺序编译 opencv 和所需的依赖库并输出到 `dist.<arch>.*`；

### 迁移和编译指南

如需配置架构，请参考注释修改 `setup2.sh` 的 `OHOS_CPU` 和 `OHOS_ARCH` 定义，或者调用 `builder.sh` 时指定 `--cpu` 参数（可选 `aarch64/arm/x86_64`）即可。

请使用 `./pkgs-create.sh` 从模板创建一个迁移工具。举例：

```shell
./pkgs-create.sh foo
# 多个包这么创建：
# ./pkgs-create.sh foo bar bazz
```

现在就成功创建了一个 foo 包，你需要按照 `foo/BUILD` 中的指示填写关键信息，包括版本、依赖、构建 hooks、以及 `foo/POSTINST` 安装时 hook 脚本。

填写完成后执行 `./builder.sh foo/BUILD` 构建这个包。成功后会输出到 `dist.<arch>.foo` 目录下。

注意，`builder.sh` 本身不会管理依赖图，`ohloha` [包管理器](https://gitcode.com/openharmony-robot/tools_ohloha) 会管理并生成指令调用 `builder.sh` 构建这些包。

您在测试时可以按照依赖关系这样依次构建（按拓扑序方向从前到后）：`./builder.sh dep1/BUILD dep2/BUILD dep3/BUILD foo/BUILD`；
