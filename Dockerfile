# docker build . --tag=juicy-llvm
# docker build . --tag=juicy-llvm --target=juicysfplugin_win32_x64
# docker run -it --rm --name juicy-llvm juicy-llvm

# used for host-native work and for cross-compile-to-win32 work.
# works fine on 22.10 too, but we align with DEPS_UBUNTU_VER
# to save some image fetching (if the version gap were bigger than this,
# then we'd instead prefer to keep UBUNTU_VER as new as it can go, to have
# access to latest toolchains and deps from apt)
ARG UBUNTU_VER=22.04
# oldest Ubuntu on which we can build Linux targets successfully.
# this is basically "how old a glibc should juicy + its dependencies to target".
# older is better (support more systems).
# sadly 20.04 encountered undefined symbols linking freetype into juicysfplugin,
# and even 21.04 had missing symbol _dlopen.
# 21.04 is probably solveable (add -dl flag in right position), but
# for now we target 22.04 because it's the oldest LTS that works without
# further accommodations.
# https://ubuntu.com/blog/what-is-an-ubuntu-lts-release
ARG DEPS_UBUNTU_VER=22.04

FROM ubuntu:$UBUNTU_VER AS toolchain-common
# xz-utils - for extracting llvm-mingw releases
# zstd - for extracting MSYS2 packages
# lib* - needed to build host-native juceaide
RUN apt-get update -qq && \
DEBIAN_FRONTEND=noninteractive apt-get install -qqy --no-install-recommends \
wget ca-certificates \
git xz-utils \
cmake clang make pkg-config \
libx11-dev libxrandr-dev libxinerama-dev libxcursor-dev libfreetype6-dev \
zstd \
&& \
apt-get clean -y && \
rm -rf /var/lib/apt/lists/*

FROM toolchain-common AS llvm_mingw
COPY llvm-scripts/download_llvm_mingw.sh download_llvm_mingw.sh
ARG LLVM_MINGW_VER=20220323
RUN LLVM_MINGW_VER=$LLVM_MINGW_VER ./download_llvm_mingw.sh download_llvm_mingw.sh
# here's how to merge it into existing /bin, but that could have unintended clashes
# RUN tar -xvf llvm-mingw.tar.xz --strip-components=1 -k && rm llvm-mingw.tar.xz
RUN mkdir -p /opt/llvm-mingw && tar -xvf llvm-mingw.tar.xz --strip-components=1 -C /opt/llvm-mingw && rm llvm-mingw.tar.xz
ENV PATH="/opt/llvm-mingw/bin:$PATH"

FROM ubuntu:$DEPS_UBUNTU_VER AS linux_xcompile
# automake, libtool, git, ca-certificates needed to build libasound
# libx* to build JUCE GUI plugins
# lib* - dependencies of libfreetype, which juicysfplugin needs on Linux
#   instead of installing libfreetype6-dev, we install its lib* dependencies
#   and compile it ourselves (we need a libfreetype.a compiled with -fPIC,
#   so we can link it into our libjuicysfplugin.so when we target Linux VST)
RUN apt-get update -qq && \
DEBIAN_FRONTEND=noninteractive apt-get install -qqy --no-install-recommends \
automake libtool git ca-certificates \
cmake make pkg-config clang lld llvm \
&& \
apt-get clean -y && \
rm -rf /var/lib/apt/lists/*
COPY llvm-scripts/multi-arch-apt.sh multi-arch-apt.sh
RUN ./multi-arch-apt.sh
COPY llvm-scripts/alsa/clone_alsa.sh clone_alsa.sh
RUN ./clone_alsa.sh
COPY llvm-scripts/get_fluidsynth_deps_linux.sh get_fluidsynth_deps_linux.sh

FROM linux_xcompile AS linux_deps_aarch64
RUN ./get_fluidsynth_deps_linux.sh arm64
COPY llvm-scripts/alsa/configure_alsa.sh configure_alsa.sh
RUN ./configure_alsa.sh aarch64
COPY llvm-scripts/alsa/make_alsa.sh make_alsa.sh
RUN ./make_alsa.sh aarch64
COPY llvm-scripts/toolchain/linux_arm64_toolchain.cmake /linux_arm64_toolchain.cmake
COPY llvm-scripts/freetype/clone_freetype.sh clone_freetype.sh
RUN ./clone_freetype.sh
COPY llvm-scripts/freetype/configure_freetype.sh configure_freetype.sh
RUN ./configure_freetype.sh aarch64
COPY llvm-scripts/freetype/make_freetype.sh make_freetype.sh
RUN ./make_freetype.sh aarch64

FROM linux_xcompile AS linux_deps_x86_64
RUN ./get_fluidsynth_deps_linux.sh amd64
COPY llvm-scripts/alsa/configure_alsa.sh configure_alsa.sh
RUN ./configure_alsa.sh x86_64
COPY llvm-scripts/alsa/make_alsa.sh make_alsa.sh
RUN ./make_alsa.sh x86_64
COPY llvm-scripts/toolchain/linux_amd64_toolchain.cmake /linux_amd64_toolchain.cmake
COPY llvm-scripts/freetype/clone_freetype.sh clone_freetype.sh
RUN ./clone_freetype.sh
COPY llvm-scripts/freetype/configure_freetype.sh configure_freetype.sh
RUN ./configure_freetype.sh x86_64
COPY llvm-scripts/freetype/make_freetype.sh make_freetype.sh
RUN ./make_freetype.sh x86_64

FROM linux_xcompile AS linux_deps_i386
RUN ./get_fluidsynth_deps_linux.sh i386
COPY llvm-scripts/alsa/configure_alsa.sh configure_alsa.sh
RUN ./configure_alsa.sh i386
COPY llvm-scripts/alsa/make_alsa.sh make_alsa.sh
RUN ./make_alsa.sh i386
COPY llvm-scripts/toolchain/linux_i386_toolchain.cmake /linux_i386_toolchain.cmake
COPY llvm-scripts/freetype/clone_freetype.sh clone_freetype.sh
RUN ./clone_freetype.sh
COPY llvm-scripts/freetype/configure_freetype.sh configure_freetype.sh
RUN ./configure_freetype.sh i386
COPY llvm-scripts/freetype/make_freetype.sh make_freetype.sh
RUN ./make_freetype.sh i386

FROM toolchain-common AS get_fluidsynth
COPY llvm-scripts/fluidsynth/clone_fluidsynth.sh clone_fluidsynth.sh
RUN ./clone_fluidsynth.sh

FROM toolchain-common AS get_juce
COPY llvm-scripts/juce/clone_juce.sh clone_juce.sh
RUN ./clone_juce.sh

FROM toolchain-common AS make_juce
COPY llvm-scripts/juce/clone_juce.sh clone_juce.sh
RUN ./clone_juce.sh
COPY llvm-scripts/juce/make_juce.sh make_juce.sh
RUN ./make_juce.sh

# FROM toolchain-common AS get_freetype
# COPY llvm-scripts/freetype/clone_freetype.sh clone_freetype.sh
# RUN ./clone_freetype.sh

# FROM get_freetype AS freetype_aarch64
# COPY llvm-scripts/freetype/configure_freetype.sh configure_freetype.sh
# RUN ./configure_freetype.sh aarch64
# COPY llvm-scripts/freetype/make_freetype.sh make_freetype.sh
# RUN ./make_freetype.sh aarch64

# FROM get_freetype AS freetype_x86_64
# COPY llvm-scripts/freetype/configure_freetype.sh configure_freetype.sh
# RUN ./configure_freetype.sh x86_64
# COPY llvm-scripts/freetype/make_freetype.sh make_freetype.sh
# RUN ./make_freetype.sh x86_64

# FROM get_freetype AS freetype_i386
# COPY llvm-scripts/freetype/configure_freetype.sh configure_freetype.sh
# RUN ./configure_freetype.sh i386
# COPY llvm-scripts/freetype/make_freetype.sh make_freetype.sh
# RUN ./make_freetype.sh i386

FROM toolchain-common AS msys2_deps
COPY llvm-scripts/get_fluidsynth_deps_win32.sh get_fluidsynth_deps_win32.sh

FROM msys2_deps AS msys2_deps_x64
RUN ./get_fluidsynth_deps_win32.sh x64

FROM msys2_deps AS msys2_deps_x86
RUN ./get_fluidsynth_deps_win32.sh x86

FROM msys2_deps AS msys2_deps_aarch64
RUN ./get_fluidsynth_deps_win32.sh arm64

FROM llvm_mingw AS make_fluidsynth_win32_x64
COPY --from=msys2_deps_x64 clang64 clang64
COPY --from=get_fluidsynth fluidsynth fluidsynth
COPY llvm-scripts/toolchain/win32_x86_64_toolchain.cmake /win32_x86_64_toolchain.cmake
COPY llvm-scripts/fluidsynth/configure_fluidsynth.sh configure_fluidsynth.sh
RUN ./configure_fluidsynth.sh win32 x64
COPY llvm-scripts/fluidsynth/make_fluidsynth.sh make_fluidsynth.sh
RUN ./make_fluidsynth.sh win32 x64

FROM llvm_mingw AS make_fluidsynth_win32_x86
COPY --from=msys2_deps_x86 clang32 clang32
COPY --from=get_fluidsynth fluidsynth fluidsynth
COPY llvm-scripts/toolchain/win32_i686_toolchain.cmake /win32_i686_toolchain.cmake
COPY llvm-scripts/fluidsynth/configure_fluidsynth.sh configure_fluidsynth.sh
RUN ./configure_fluidsynth.sh win32 x86
COPY llvm-scripts/fluidsynth/make_fluidsynth.sh make_fluidsynth.sh
RUN ./make_fluidsynth.sh win32 x86

FROM llvm_mingw AS make_fluidsynth_win32_aarch64
COPY --from=msys2_deps_aarch64 clangarm64 clangarm64
COPY --from=get_fluidsynth fluidsynth fluidsynth
COPY llvm-scripts/toolchain/win32_aarch64_toolchain.cmake /win32_aarch64_toolchain.cmake
COPY llvm-scripts/fluidsynth/configure_fluidsynth.sh configure_fluidsynth.sh
RUN ./configure_fluidsynth.sh win32 arm64
COPY llvm-scripts/fluidsynth/make_fluidsynth.sh make_fluidsynth.sh
RUN ./make_fluidsynth.sh win32 arm64

FROM linux_deps_x86_64 AS make_fluidsynth_linux_x86_64
COPY --from=get_fluidsynth fluidsynth fluidsynth
COPY llvm-scripts/fluidsynth/configure_fluidsynth.sh configure_fluidsynth.sh
RUN ./configure_fluidsynth.sh linux x64
COPY llvm-scripts/fluidsynth/make_fluidsynth.sh make_fluidsynth.sh
RUN ./make_fluidsynth.sh linux x64

FROM linux_deps_i386 AS make_fluidsynth_linux_i386
COPY --from=get_fluidsynth fluidsynth fluidsynth
COPY llvm-scripts/fluidsynth/configure_fluidsynth.sh configure_fluidsynth.sh
RUN ./configure_fluidsynth.sh linux x86
COPY llvm-scripts/fluidsynth/make_fluidsynth.sh make_fluidsynth.sh
RUN ./make_fluidsynth.sh linux x86

FROM linux_deps_aarch64 AS make_fluidsynth_linux_aarch64
COPY --from=get_fluidsynth fluidsynth fluidsynth
COPY llvm-scripts/fluidsynth/configure_fluidsynth.sh configure_fluidsynth.sh
RUN ./configure_fluidsynth.sh linux arm64
COPY llvm-scripts/fluidsynth/make_fluidsynth.sh make_fluidsynth.sh
RUN ./make_fluidsynth.sh linux arm64

FROM llvm_mingw AS juicysfplugin_common_win32
COPY --from=make_juce /linux_native/ /linux_native/
WORKDIR juicysfplugin
COPY resources/Logo512.png resources/Logo512.png
COPY VST2_SDK/ /VST2_SDK/
COPY llvm-scripts/juicysfplugin/configure_juicysfplugin.sh configure_juicysfplugin.sh
COPY cmake/Modules/FindPkgConfig.cmake cmake/Modules/FindPkgConfig.cmake
COPY CMakeLists.txt CMakeLists.txt
COPY Source/ Source/
COPY JuceLibraryCode/JuceHeader.h JuceLibraryCode/JuceHeader.h
COPY llvm-scripts/fix_mingw_headers.sh fix_mingw_headers.sh
RUN ./fix_mingw_headers.sh
COPY llvm-scripts/attrib_noop.sh /usr/local/bin/attrib

FROM juicysfplugin_common_win32 AS juicysfplugin_win32_x64
COPY --from=msys2_deps_x64 /clang64/ /clang64/
COPY --from=make_fluidsynth_win32_x64 /clang64/include/fluidsynth.h /clang64/include/fluidsynth.h
COPY --from=make_fluidsynth_win32_x64 /clang64/include/fluidsynth/ /clang64/include/fluidsynth/
COPY --from=make_fluidsynth_win32_x64 /clang64/lib/pkgconfig/fluidsynth.pc /clang64/lib/pkgconfig/fluidsynth.pc
COPY --from=make_fluidsynth_win32_x64 /clang64/lib/libfluidsynth.a /clang64/lib/libfluidsynth.a
COPY llvm-scripts/toolchain/win32_x86_64_toolchain.cmake /win32_x86_64_toolchain.cmake
RUN /juicysfplugin/configure_juicysfplugin.sh win32 x64
COPY llvm-scripts/juicysfplugin/make_juicysfplugin.sh make_juicysfplugin.sh
RUN /juicysfplugin/make_juicysfplugin.sh win32 x64

FROM juicysfplugin_common_win32 AS juicysfplugin_win32_x86
COPY --from=msys2_deps_x86 /clang32/ /clang32/
COPY --from=make_fluidsynth_win32_x86 /clang32/include/fluidsynth.h /clang32/include/fluidsynth.h
COPY --from=make_fluidsynth_win32_x86 /clang32/include/fluidsynth/ /clang32/include/fluidsynth/
COPY --from=make_fluidsynth_win32_x86 /clang32/lib/pkgconfig/fluidsynth.pc /clang32/lib/pkgconfig/fluidsynth.pc
COPY --from=make_fluidsynth_win32_x86 /clang32/lib/libfluidsynth.a /clang32/lib/libfluidsynth.a
COPY llvm-scripts/toolchain/win32_i686_toolchain.cmake /win32_i686_toolchain.cmake
RUN /juicysfplugin/configure_juicysfplugin.sh win32 x86
COPY llvm-scripts/juicysfplugin/make_juicysfplugin.sh make_juicysfplugin.sh
RUN /juicysfplugin/make_juicysfplugin.sh win32 x86

FROM juicysfplugin_common_win32 AS juicysfplugin_win32_aarch64
COPY --from=msys2_deps_aarch64 /clangarm64/ /clangarm64/
COPY --from=make_fluidsynth_win32_aarch64 /clangarm64/include/fluidsynth.h /clangarm64/include/fluidsynth.h
COPY --from=make_fluidsynth_win32_aarch64 /clangarm64/include/fluidsynth/ /clangarm64/include/fluidsynth/
COPY --from=make_fluidsynth_win32_aarch64 /clangarm64/lib/pkgconfig/fluidsynth.pc /clangarm64/lib/pkgconfig/fluidsynth.pc
COPY --from=make_fluidsynth_win32_aarch64 /clangarm64/lib/libfluidsynth.a /clangarm64/lib/libfluidsynth.a
COPY llvm-scripts/toolchain/win32_aarch64_toolchain.cmake /win32_aarch64_toolchain.cmake
RUN /juicysfplugin/configure_juicysfplugin.sh win32 arm64
COPY llvm-scripts/juicysfplugin/make_juicysfplugin.sh make_juicysfplugin.sh
RUN /juicysfplugin/make_juicysfplugin.sh win32 arm64

FROM linux_deps_x86_64 AS juicysfplugin_linux_x86_64
COPY --from=make_juce /linux_native/ /linux_native/
WORKDIR juicysfplugin
COPY --from=linux_deps_x86_64 /usr/lib/x86_64-linux-gnu /usr/lib/x86_64-linux-gnu
COPY --from=make_fluidsynth_linux_x86_64 /usr/include/fluidsynth.h /usr/include/fluidsynth.h
COPY --from=make_fluidsynth_linux_x86_64 /usr/include/fluidsynth/ /usr/include/fluidsynth/
COPY --from=make_fluidsynth_linux_x86_64 /usr/lib/x86_64-linux-gnu/pkgconfig/fluidsynth.pc /usr/lib/x86_64-linux-gnu/pkgconfig/fluidsynth.pc
COPY --from=make_fluidsynth_linux_x86_64 /usr/lib/x86_64-linux-gnu/libfluidsynth.a /usr/lib/x86_64-linux-gnu/libfluidsynth.a
COPY llvm-scripts/toolchain/linux_amd64_toolchain.cmake /linux_amd64_toolchain.cmake
COPY resources/Logo512.png resources/Logo512.png
COPY VST2_SDK/ /VST2_SDK/
COPY cmake/Modules/FindPkgConfig.cmake cmake/Modules/FindPkgConfig.cmake
COPY CMakeLists.txt CMakeLists.txt
COPY Source/ Source/
COPY JuceLibraryCode/JuceHeader.h JuceLibraryCode/JuceHeader.h
COPY llvm-scripts/juicysfplugin/configure_juicysfplugin.sh configure_juicysfplugin.sh
RUN ./configure_juicysfplugin.sh linux x64
COPY llvm-scripts/juicysfplugin/make_juicysfplugin.sh make_juicysfplugin.sh
# RUN ./make_juicysfplugin.sh linux x64

FROM linux_deps_i386 AS juicysfplugin_linux_i386
COPY --from=make_juce /linux_native/ /linux_native/
WORKDIR juicysfplugin
COPY --from=linux_deps_i386 /usr/lib/i386-linux-gnu /usr/lib/i386-linux-gnu
COPY --from=make_fluidsynth_linux_i386 /usr/include/fluidsynth.h /usr/include/fluidsynth.h
COPY --from=make_fluidsynth_linux_i386 /usr/include/fluidsynth/ /usr/include/fluidsynth/
COPY --from=make_fluidsynth_linux_i386 /usr/lib/i386-linux-gnu/pkgconfig/fluidsynth.pc /usr/lib/i386-linux-gnu/pkgconfig/fluidsynth.pc
COPY --from=make_fluidsynth_linux_i386 /usr/lib/i386-linux-gnu/libfluidsynth.a /usr/lib/i386-linux-gnu/libfluidsynth.a
COPY llvm-scripts/toolchain/linux_i386_toolchain.cmake /linux_i386_toolchain.cmake
COPY resources/Logo512.png resources/Logo512.png
COPY VST2_SDK/ /VST2_SDK/
COPY cmake/Modules/FindPkgConfig.cmake cmake/Modules/FindPkgConfig.cmake
COPY CMakeLists.txt CMakeLists.txt
COPY Source/ Source/
COPY JuceLibraryCode/JuceHeader.h JuceLibraryCode/JuceHeader.h
COPY llvm-scripts/juicysfplugin/configure_juicysfplugin.sh configure_juicysfplugin.sh
RUN ./configure_juicysfplugin.sh linux x86
COPY llvm-scripts/juicysfplugin/make_juicysfplugin.sh make_juicysfplugin.sh
RUN ./make_juicysfplugin.sh linux x86

FROM linux_deps_aarch64 AS juicysfplugin_linux_aarch64
COPY --from=make_juce /linux_native/ /linux_native/
WORKDIR juicysfplugin
COPY --from=linux_deps_aarch64 /usr/lib/aarch64-linux-gnu /usr/lib/aarch64-linux-gnu
COPY --from=linux_deps_aarch64 /usr/include/freetype/ /usr/include/freetype/
COPY --from=linux_deps_aarch64 /usr/include/ft2build.h /usr/include/ft2build.h
COPY --from=make_fluidsynth_linux_aarch64 /usr/include/fluidsynth.h /usr/include/fluidsynth.h
COPY --from=make_fluidsynth_linux_aarch64 /usr/include/fluidsynth/ /usr/include/fluidsynth/
COPY --from=make_fluidsynth_linux_aarch64 /usr/lib/aarch64-linux-gnu/pkgconfig/fluidsynth.pc /usr/lib/aarch64-linux-gnu/pkgconfig/fluidsynth.pc
COPY --from=make_fluidsynth_linux_aarch64 /usr/lib/aarch64-linux-gnu/libfluidsynth.a /usr/lib/aarch64-linux-gnu/libfluidsynth.a
COPY llvm-scripts/toolchain/linux_arm64_toolchain.cmake /linux_arm64_toolchain.cmake
COPY resources/Logo512.png resources/Logo512.png
COPY VST2_SDK/ /VST2_SDK/
COPY cmake/Modules/FindPkgConfig.cmake cmake/Modules/FindPkgConfig.cmake
COPY CMakeLists.txt CMakeLists.txt
COPY Source/ Source/
COPY JuceLibraryCode/JuceHeader.h JuceLibraryCode/JuceHeader.h
COPY llvm-scripts/juicysfplugin/configure_juicysfplugin.sh configure_juicysfplugin.sh
RUN ./configure_juicysfplugin.sh linux arm64
COPY llvm-scripts/juicysfplugin/make_juicysfplugin.sh make_juicysfplugin.sh
RUN ./make_juicysfplugin.sh linux arm64

FROM ubuntu:$UBUNTU_VER AS distribute
COPY --from=juicysfplugin_linux_x86_64 /juicysfplugin/build_linux_x64/JuicySFPlugin_artefacts/ /linux_x64/
COPY --from=juicysfplugin_linux_i386 /juicysfplugin/build_linux_x86/JuicySFPlugin_artefacts/ /linux_x86/
# aarch64 fails due to a few static libraries' not being compiled with -fPIC
# (e.g. libfreetype.a libpng16.a libogg.a and *maybe* libstdc++,
# which complained about std::_Sp_make_shared_tag::_S_ti()::__tag )
# COPY --from=juicysfplugin_linux_aarch64 /juicysfplugin/build_linux_arm64/JuicySFPlugin_artefacts/ /linux_arm64/
COPY --from=juicysfplugin_win32_x64 /juicysfplugin/build_win32_x64/JuicySFPlugin_artefacts/ /win32_x64/
COPY --from=juicysfplugin_win32_x86 /juicysfplugin/build_win32_x86/JuicySFPlugin_artefacts/ /win32_x86/
## win32 aarch64 fails to compile asm in juce_win32_SystemStats.cpp
COPY --from=juicysfplugin_win32_aarch64 /juicysfplugin/build_win32_arm64/JuicySFPlugin_artefacts/ /win32_arm64/