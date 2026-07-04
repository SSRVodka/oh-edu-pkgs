# NOTE: this file only support Ubuntu < 26.04
apt install -y lsb-release wget software-properties-common gnupg curl
apt install -y build-essential file patchelf bison flex nasm texinfo perl automake autoconf autopoint libtool libtool-bin m4 po4a
# python deps
# Change lzma-dev to liblzma-dev, libncurses5-dev to libncurses-dev, libreadline6-dev to libreadline-dev in ubuntu >= 26.04
apt install -y gdb lcov pkg-config libbz2-dev libffi-dev liblzma-dev libncurses5-dev libreadline6-dev libsqlite3-dev libssl-dev lzma lzma-dev uuid-dev zlib1g-dev libmpdec-dev libzstd-dev zstd inetutils-inetd
# zstd deps
apt install -y ninja-build
# pypkgs deps
apt install -y git zip
# grpc host build
apt install -y cmake
# mesa deps
apt install -y glslang-tools
# fontconfig deps
apt install -y gperf
# openjdk deps: use same jdk version as bootstrap JDK; no libstdc++-12-dev to avoid using default glibc
apt install -y openjdk-21-jdk libc6-dev libc++-12-dev libc++abi-12-dev clang llvm lldb lld
