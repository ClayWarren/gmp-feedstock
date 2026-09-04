#!/bin/bash

set -ex

# Get an updated config.sub and config.guess
cp $BUILD_PREFIX/share/gnuconfig/config.guess config.fsf.guess
cp $BUILD_PREFIX/share/gnuconfig/config.sub config.fsf.sub

chmod +x configure

# GMP 6.3.0 predates C23; GCC 15 (riscv64) defaults to it and rejects
# configure's compiler probes. Force the older standard.
export CFLAGS="${CFLAGS} -std=gnu17"

if [[ "$target_platform" == "win-arm64" ]]; then
  # The native compiler is ARM64, but the MSYS2 userland runs under x64
  # emulation. Avoid config.guess identifying the build machine as x86_64.
  export build_alias=aarch64-pc-mingw32
  export host_alias=aarch64-pc-mingw32

  # GMP's ARM64 assembly needs the COFF target and a compile-only invocation.
  export CCAS=clang.exe
  export ASMFLAGS="-c --target=arm64-pc-windows-msvc"

  # These are the native Windows configure answers used by vcpkg's GMP port.
  export ac_cv_func_memset=yes
  export gmp_cv_asm_w32=.word
  export gmp_cv_check_libm_for_build=no

  autoreconf -vfi

  # Libtool mistakes clang.exe for cl.exe because its compiler-name check is
  # prefix based. Keep its complete export list, but pass each MSVC-style
  # export option through the GNU Clang driver to LLD explicitly.
  old_export_template='s/^/-link -EXPORT:/'
  new_export_template='s/^/-Xlinker -EXPORT:/'
  old_export_count=$(grep -Fc -- "$old_export_template" configure || true)
  if [[ "$old_export_count" -ne 2 ]]; then
    echo "Expected two libtool Windows export templates, found $old_export_count" >&2
    exit 1
  fi
  sed 's|s/^/-link -EXPORT:/|s/^/-Xlinker -EXPORT:/|g' configure > configure.fixed
  mv configure.fixed configure
  chmod +x configure
  old_export_count=$(grep -Fc -- "$old_export_template" configure || true)
  new_export_count=$(grep -Fc -- "$new_export_template" configure || true)
  if [[ "$old_export_count" -ne 0 || "$new_export_count" -ne 2 ]]; then
    echo "Failed to correct both libtool Windows export templates" >&2
    exit 1
  fi
fi

mkdir build
cd build

if [[ "$target_platform" == "linux-ppc64le" ]]; then
  # HOST="powerpc64le-conda-linux-gnu" masks the fact that we are only
  # building for power8 and uses an older POWER architecture.
  CONFIGURE_ARGS="--host=power8-pc-linux-gnu"
elif [[ "$target_platform" == "win-arm64" ]]; then
  CONFIGURE_ARGS="--build=$build_alias --host=$host_alias"
else
  CONFIGURE_ARGS="--host=$CONDA_TOOLCHAIN_HOST"
fi

if [[ "$target_platform" == win-* ]]; then
  export PREFIX=${PREFIX}/Library
else
  CONFIGURE_ARGS="$CONFIGURE_ARGS --enable-cxx"
fi

if [[ "$target_platform" == "win-arm64" ]]; then
  FAT_ARG="--disable-fat"
else
  FAT_ARG="--enable-fat"
fi

../configure \
  --prefix=${PREFIX} \
  $FAT_ARG \
  --enable-shared \
  --disable-static \
  $CONFIGURE_ARGS || (cat config.log; exit 1)

make -j${CPU_COUNT}
if [[ "${CONDA_BUILD_CROSS_COMPILATION}" != "1" ]]; then
  if ! make check -j${CPU_COUNT}; then
    if [[ "$target_platform" == "win-arm64" ]]; then
      while IFS= read -r test_log; do
        echo "===== $test_log ====="
        cat "$test_log"
      done < <(find tests -type f -name '*.log' -print | sort)
    fi
    exit 1
  fi
fi
make install

if [[ "$target_platform" == "win-64" ]]; then
  gendef $PREFIX/bin/libgmp-10.dll
  $CONDA_TOOLCHAIN_HOST-dlltool -d libgmp-10.def -l $PREFIX/lib/gmp.lib
elif [[ "$target_platform" == "win-arm64" ]]; then
  if [[ -f "$PREFIX/lib/libgmp.dll.lib" ]]; then
    mv "$PREFIX/lib/libgmp.dll.lib" "$PREFIX/lib/gmp.lib"
  elif [[ ! -f "$PREFIX/lib/gmp.lib" ]]; then
    echo "GMP did not install an MSVC import library" >&2
    find "$PREFIX/lib" -maxdepth 1 -type f -print >&2
    exit 1
  fi
fi

if [[ "$target_platform" == "linux-ppc64le" ]]; then
    # Build a Power9 library as well
    cd .. && mkdir build2 && cd build2
    CFLAGS=$(echo "${CFLAGS}" | sed "s/=power8/=power9/g")
    ../configure --prefix=${PREFIX} $CONFIGURE_ARGS --host="power9-pc-linux-gnu"
    make -j${CPU_COUNT}
    make install DESTDIR=$PWD/install
    # Install just the library to $PREFIX/lib/power9
    # Since $PREFIX/lib is in the rpath, newer glibc will look in
    # $PREFIX/lib/power9 before $PREFIX/lib
    # See Rpath token expansion in http://man7.org/linux/man-pages/man8/ld.so.8.html
    # This is only done for powerpc because GMP has a fat binary for x86 and I
    # couldn't find how to do it for arm64 and not sure whether that's beneficial.
    mkdir -p $PREFIX/lib/power9
    mkdir -p $PREFIX/lib/power10
    for library in "$PWD/install$PREFIX/lib"/libgmp.so.*; do
        if [[ "${library##*/}" =~ ^libgmp\.so\.[0-9]+$ ]]; then
            cp "$library" "$PREFIX/lib/power9"
            cp "$library" "$PREFIX/lib/power10"
        fi
    done
fi
