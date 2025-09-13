# syntax=docker/dockerfile:1.4
FROM ubuntu:20.04

# The number of CPU cores to use when performing compilation
ARG CPU_CORES=8
# The version of libGMP that we will build
ARG GMP_VERSION=6.3.0
# The version of GDB that we will build
ARG GDB_VERSION=16.3
ARG MPFR_VERSION=4.2.2
ARG MPC_VERSION=1.3.1


# Install timezone data non-interactively
ENV TZ=UTC
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
# Install our build dependencies
RUN rm -f /etc/apt/apt.conf.d/docker-clean; \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        autoconf \
        automake \
        build-essential \
        ca-certificates \
        python3-dev \
        libpython3-dev \
        curl \
        tar \
        zip \
        pkg-config \
        texinfo \
        mingw-w64 \
        mingw-w64-tools \
        gcc-mingw-w64-x86-64 \
        g++-mingw-w64-x86-64 \
        make \
        unzip && \
    rm -rf /var/lib/apt/lists/*

# Create a non-root user and perform all build steps as this user (this simplifies things a little when later copying files out of the container image)
RUN useradd --create-home --home /home/nonroot --shell /bin/bash nonroot
USER nonroot

RUN echo

RUN mkdir -p /tmp/src/

RUN curl -fSL "https://github.com/pmmp/DependencyMirror/releases/download/mirror/gmp-6.3.0.tar.xz" -o "/tmp/gmp-${GMP_VERSION}.tar.xz" && \

tar xvf "/tmp/gmp-${GMP_VERSION}.tar.xz" --directory /tmp/src && rm -f "/tmp/gmp-${GMP_VERSION}.tar.xz"
# Download and extract the source code for GDB
RUN curl -fSL "https://sourceware.org/pub/gdb/releases/gdb-${GDB_VERSION}.tar.gz" -o "/tmp/gdb-${GDB_VERSION}.tar.gz" && \
tar xvf "/tmp/gdb-${GDB_VERSION}.tar.gz" --directory /tmp/src && rm -f "/tmp/gdb-${GDB_VERSION}.tar.gz"
# https://www.mpfr.org/mpfr-current/mpfr-4.2.2.tar.gz
RUN curl -fSL "https://www.mpfr.org/mpfr-current/mpfr-${MPFR_VERSION}.tar.gz" -o "/tmp/mpfr-${MPFR_VERSION}.tar.gz" && \
 tar xvf "/tmp/mpfr-${MPFR_VERSION}.tar.gz" --directory /tmp/src && rm -f "/tmp/mpfr-${MPFR_VERSION}.tar.gz"
RUN curl -fSL "https://ftp.gnu.org/gnu/mpc/mpc-${MPC_VERSION}.tar.gz" -o "/tmp/mpc-${MPC_VERSION}.tar.gz" && \
 tar xvf "/tmp/mpc-${MPC_VERSION}.tar.gz" --directory /tmp/src && rm -f "/tmp/mpc-${MPC_VERSION}.tar.gz"
WORKDIR /tmp/
RUN curl -L -o Python313.tar.gz "https://github.com/DaisukeDaisuke/empty/releases/download/1.0.0/Python313.tar.gz"
RUN mkdir -p /tmp/install/Python313
RUN tar xvf "Python313.tar.gz" --directory /tmp/install
# python runtime
RUN curl -L -o python-3.13.7-embed-amd64.zip https://www.python.org/ftp/python/3.13.7/python-3.13.7-embed-amd64.zip
RUN unzip python-3.13.7-embed-amd64.zip -d /tmp/install/python-3.13.7-embed-amd64 \ 
&& rm -f python-3.13.7-embed-amd64.zip
RUN cp -r /tmp/install/Python313/include/ /tmp/install/python-3.13.7-embed-amd64/include
RUN cp -r /tmp/install/Python313/libs/ /tmp/install/python-3.13.7-embed-amd64/libs



WORKDIR /tmp/install/python-3.13.7-embed-amd64
#（もし DLL が python313.dll の場合、python3.dll としてコピー）
#RUN cp python3.dll python3.dll
# 生成 def
RUN gendef python313.dll
# インポートライブラリを期待される名前で生成
RUN x86_64-w64-mingw32-dlltool --def python313.def --dllname python313.dll --output-lib libpython313.a
# ライブラリを lib ディレクトリへ
RUN mkdir -p /tmp/install/python-3.13.7-embed-amd64/lib && mv libpython313.a /tmp/install/python-3.13.7-embed-amd64/lib/libpython313.a

WORKDIR /

# 2) configure が呼ぶ「python 実行」をエミュレートする shim を作成
RUN cat > /tmp/install/python_shim <<'EOF' && chmod +x /tmp/install/python_shim
#!/bin/sh
# shim: $1 == path/to/python-config.py, $2 == option
case "$2" in
  --includes)
    # ヘッダが include と include/python3.13 にある可能性をカバー
    echo "-I/tmp/install/python-3.13.7-embed-amd64/include -I/tmp/install/python-3.13.7-embed-amd64/"
    exit 0
    ;;
  --ldflags)
    # ライブラリ・パスと、configure が期待する -l 名に合わせる
    echo "-L/tmp/install/python-3.13.7-embed-amd64/lib -lpython313"
    exit 0
    ;;
  --exec-prefix)
    echo "/tmp/install/python-3.13.7-embed-amd64"
    exit 0
    ;;
  --cflags)
    echo "-I/tmp/install/python-3.13.7-embed-amd64/include -I/tmp/install/python-3.13.7-embed-amd64/"
    exit 0
    ;;
  --help|--version)
    echo "python-shim (fake)"; exit 0
    ;;
  *)
    exit 1
    ;;
esac

EOF

RUN sed -i 's/\r$//' /tmp/install/python_shim

# Build GMP for MinGW-w64
RUN mkdir -p /tmp/build/gmp && cd /tmp/build/gmp && \
    "/tmp/src/gmp-${GMP_VERSION}/configure" \
        --prefix=/tmp/install/gmp \
        --host=x86_64-w64-mingw32 \
        --disable-shared \
        --enable-static \
        --enable-cxx && \
    make "-j${CPU_CORES}" && \
    make install

# Build MPFR for MinGW-w64 (depends on GMP)
RUN mkdir -p /tmp/build/mpfr && cd /tmp/build/mpfr && \
    "/tmp/src/mpfr-${MPFR_VERSION}/configure" \
        --prefix=/tmp/install/mpfr \
        --host=x86_64-w64-mingw32 \
        --with-gmp=/tmp/install/gmp \
        --disable-shared \
        --enable-static && \
    make "-j${CPU_CORES}" && \
    make install

# Build MPC for MinGW-w64 (depends on GMP and MPFR)
RUN mkdir -p /tmp/build/mpc && cd /tmp/build/mpc && \
    "/tmp/src/mpc-${MPC_VERSION}/configure" \
        --prefix=/tmp/install/mpc \
        --host=x86_64-w64-mingw32 \
        --with-gmp=/tmp/install/gmp \
        --with-mpfr=/tmp/install/mpfr \
        --disable-shared \
        --enable-static && \
    make "-j${CPU_CORES}" && \
    make install


ENV PKG_CONFIG_PATH="/tmp/install/gmp/lib/pkgconfig:/tmp/install/mpfr/lib/pkgconfig:/tmp/install/mpc/lib/pkgconfig"
ENV CPPFLAGS="-I/tmp/install/gmp/include -I/tmp/install/mpfr/include -I/tmp/install/mpc/include"
ENV LDFLAGS="-L/tmp/install/gmp/lib -L/tmp/install/mpfr/lib -L/tmp/install/mpc/lib -static-libgcc -static-libstdc++. -Wl,--gc-sections -Wl,--allow-multiple-definition"

# 2) configure & build gdb with relaxed libtool checks and without -no-undefined
RUN mkdir -p /tmp/build/gdb && cd /tmp/build/gdb && \
    export LDFLAGS="-Wl,--gc-sections -Wl,--allow-multiple-definition" && \
    env lt_cv_deplibs_check_method=pass_all \
    /tmp/src/gdb-${GDB_VERSION}/configure \
        --prefix=/tmp/install/gdb \
        --host=x86_64-w64-mingw32 \
        --target=x86_64-w64-mingw32 \
        --enable-targets=all \
        --with-gmp=/tmp/install/gmp \
        --with-mpfr=/tmp/install/mpfr \
        --with-mpc=/tmp/install/mpc \
        --with-static-standard-libraries \
        --with-python=/tmp/install/python_shim \
		--with-python-libdir=/tmp/install/python-3.13.7-embed-amd64/lib \
        --enable-static \
        --disable-shared \
        --disable-ld \
        --disable-gold \
        --disable-sim \
        --disable-werror \
        --disable-nls \
        --disable-rpath \
        --disable-tui \
        --with-system-zlib=no \
        CFLAGS="-Os -g0" \
        CXXFLAGS="-Os -g0" && \
    make -j1 MAKEINFO=true V=1 && \
    make install MAKEINFO=true

# # When modifying Docker below this point, do not recompile GDB.
# RUN echo test

# Retrieve the license files for GCC
RUN mkdir -p /tmp/dist/licenses/gcc && \
    curl -fSL 'https://raw.githubusercontent.com/gcc-mirror/gcc/master/COPYING3' -o /tmp/dist/licenses/gcc/COPYING3 && \
    curl -fSL 'https://raw.githubusercontent.com/gcc-mirror/gcc/master/COPYING.RUNTIME' -o /tmp/dist/licenses/gcc/COPYING.RUNTIME

# # Copy the GDB executable and strip debug symbols
#RUN mkdir /tmp/dist
RUN cp /tmp/install/gdb/bin/gdb.exe /tmp/dist/gdb-multiarch.exe
RUN cp /tmp/install/gdb/bin/gdbserver.exe /tmp/dist/gdbserver-multiarch.exe
RUN x86_64-w64-mingw32-strip -s /tmp/dist/gdb-multiarch.exe
RUN x86_64-w64-mingw32-strip -s /tmp/dist/gdbserver-multiarch.exe

# # Copy the license files for GDB and its dependencies
RUN mkdir -p /tmp/dist/licenses/gdb
RUN mkdir -p /tmp/dist/licenses/gdb && cp "/tmp/src/gdb-${GDB_VERSION}/COPYING" /tmp/dist/licenses/gdb/
RUN mkdir -p /tmp/dist/licenses/gmp && cp "/tmp/src/gmp-${GMP_VERSION}/COPYING" /tmp/dist/licenses/gmp/
RUN mkdir -p /tmp/dist/licenses/mpfr && cp "/tmp/src/mpfr-${MPFR_VERSION}/COPYING" /tmp/dist/licenses/mpfr/
RUN mkdir -p /tmp/dist/licenses/mpc && cp "/tmp/src/mpc-${MPC_VERSION}/COPYING.LESSER" /tmp/dist/licenses/mpc/
RUN mkdir -p /tmp/dist/licenses/bfd && cp "/tmp/src/gdb-${GDB_VERSION}/bfd/COPYING" /tmp/dist/licenses/bfd/
RUN mkdir -p /tmp/dist/licenses/libiberty && cp "/tmp/src/gdb-${GDB_VERSION}/libiberty/COPYING.LIB" /tmp/dist/licenses/libiberty/
RUN mkdir -p /tmp/dist/licenses/zlib && cp "/tmp/src/gdb-${GDB_VERSION}/zlib/README" /tmp/dist/licenses/zlib/
RUN mkdir -p /tmp/dist/licenses/Python && cp "/tmp/install/Python313/LICENSE.txt" /tmp/dist/licenses/Python/

# GDB がインストール時に作る data dir の Python モジュールをコピー
RUN mkdir -p /tmp/dist/share/gdb/python
RUN cp -r /tmp/install/gdb/share/gdb/python/* /tmp/dist/share/gdb/python/

# copy python
RUN cp -r "/tmp/install/python-3.13.7-embed-amd64/." /tmp/dist/

WORKDIR /
USER root

# cleanup artifact
RUN ls -al "/tmp/dist/include"
RUN rm -rf "/tmp/dist/include"
RUN rm -rf "/tmp/dist/lib/libs"
RUN rm -f "/tmp/dist/lib/python313.a"


# ghidragdb Python モジュールを site-packages 配下にコピー
RUN mkdir -p /tmp/dist/Lib/site-packages/ghidragdb
RUN curl -fSL https://raw.githubusercontent.com/Comsecuris/gdbghidra/refs/heads/master/data/gdb_ghidra_bridge_client.py \
    -o /tmp/dist/Lib/site-packages/ghidragdb/gdb_ghidra_bridge_client.py
# # Create a README file
RUN echo 'This directory contains a distribution of the following software:' > /tmp/dist/README.txt && \
    echo '- GNU Project Debugger (GDB) for Windows (statically linked)' >> /tmp/dist/README.txt && \
    echo '- Python 3.13 embedded runtime' >> /tmp/dist/README.txt && \
    echo '- ghidragdb Python module for Ghidra debugging' >> /tmp/dist/README.txt && \
    echo '' >> /tmp/dist/README.txt && \
    echo 'This distribution was cross-compiled on Linux using MinGW-w64.' >> /tmp/dist/README.txt && \
    echo '' >> /tmp/dist/README.txt && \
    echo 'Included licenses can be found in the `licenses` subdirectory.' >> /tmp/dist/README.txt && \
    echo '' >> /tmp/dist/README.txt && \
    echo 'Source code for each component:' >> /tmp/dist/README.txt && \
    echo "- GDB: https://ftp.gnu.org/gnu/gdb/gdb-${GDB_VERSION}.tar.gz" >> /tmp/dist/README.txt && \
    echo "- GMP: https://gmplib.org/download/gmp/gmp-${GMP_VERSION}.tar.xz" >> /tmp/dist/README.txt && \
    echo "- MPFR: https://www.mpfr.org/mpfr-current/mpfr-${MPFR_VERSION}.tar.gz" >> /tmp/dist/README.txt && \
    echo "- MPC: https://ftp.gnu.org/gnu/mpc/mpc-${MPC_VERSION}.tar.gz" >> /tmp/dist/README.txt && \
    echo "- GCC: https://github.com/gcc-mirror/gcc" >> /tmp/dist/README.txt && \
    echo "- Python 3.13: https://www.python.org/ftp/python/3.13.0/Python-3.13.0.tgz" >> /tmp/dist/README.txt && \
    echo "- Ghidra/ghidragdb: https://github.com/ghidra/ghidra" >> /tmp/dist/README.txt && \
    echo '' >> /tmp/dist/README.txt && \
    echo 'To use GDB with Python modules, ensure that PYTHONHOME and PYTHONPATH point to the included Python runtime and site-packages.' >> /tmp/dist/README.txt

WORKDIR /tmp

RUN ls -al /tmp/dist/

# Create a ZIP archive of the files for distribution
RUN mv /tmp/dist "/tmp/gdb-${GDB_VERSION}-ghidra" && \
    cd /tmp && \
    zip -r "/tmp/gdb-ghidra.zip" "gdb-${GDB_VERSION}-ghidra"




# docker build -t gdb .
# docker create gdb
# docker cp b649f7bc94b08e634c4cd2f0b8e14940b30741c896b577d3deb7e4a1dbcab50b:/artifact/gdb-ghidra.zip ./
