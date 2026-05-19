#!/usr/bin/env bash
set -e

## Based on build/posix.sh from lovell/sharp-libvips (Apache 2.0)
## Copyright 2017 Lovell Fuller and others.
## SPDX-License-Identifier: Apache-2.0

# Dependency version numbers — use Docker path /packaging/ if available (CI),
# otherwise the local repo root (direct invocation via build.sh)
if [ -f /packaging/versions.properties ]; then
  source /packaging/versions.properties
fi

without_patch() {
  echo "${1%.[[:digit:]]*}"
}
without_prerelease() {
  echo "${1%-[[:alnum:]]*}"
}

# Environment / working directories
case ${PLATFORM} in
  linux*)
    LINUX=true
    DEPS=/deps
    TARGET=/target
    PACKAGE=/packaging
    ROOT=/root
    VIPS_CPP_DEP=libvips-cpp.so.$(without_prerelease $VERSION_VIPS)
    ;;
  darwin*)
    DARWIN=true
    DEPS=$PWD/deps
    TARGET=$PWD/target
    PACKAGE=$PWD
    ROOT=$PWD/platforms/$PLATFORM
    VIPS_CPP_DEP=libvips-cpp.$(without_prerelease $VERSION_VIPS).dylib
    ;;
esac

mkdir ${DEPS}
mkdir ${TARGET}

export FLAGS+=" -Os -fPIC"

if [ "$LINUX" = true ]; then
  export FLAGS+=" -fno-asynchronous-unwind-tables -ffunction-sections -fdata-sections"
fi

export PKG_CONFIG_LIBDIR="${TARGET}/lib/pkgconfig"
export PATH="${PATH}:${TARGET}/bin"
export LD_LIBRARY_PATH="${TARGET}/lib"
export CFLAGS="${FLAGS}"
export CXXFLAGS="${FLAGS}"
export OBJCFLAGS="${FLAGS}"
export OBJCXXFLAGS="${FLAGS}"
export CPPFLAGS="-I${TARGET}/include"
export LDFLAGS="-L${TARGET}/lib"

# On Linux, we need to create a relocatable library
if [ "$LINUX" = true ]; then
  export LDFLAGS+=" -Wl,--gc-sections -Wl,-rpath=\$ORIGIN/"
fi

if [ "$DARWIN" = true ]; then
  export LDFLAGS+=" -Wl,-dead_strip"
  export CARGO_HOME="${DEPS}/cargo"
  export RUSTUP_HOME="${DEPS}/rustup"
  mkdir -p $CARGO_HOME
  mkdir -p $RUSTUP_HOME
  export PATH="${CARGO_HOME}/bin:${PATH}"
fi

if [ "$LINUX" = true ]; then
  export MAKEFLAGS="-j$(nproc)"
elif [ "$DARWIN" = true ]; then
  export MAKEFLAGS="-j$(sysctl -n hw.logicalcpu)"
fi

export TARGET_SYSROOT="${TARGET}"

export CARGO_PROFILE_RELEASE_DEBUG=false
export CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1
export CARGO_PROFILE_RELEASE_INCREMENTAL=false
export CARGO_PROFILE_RELEASE_LTO=true
export CARGO_PROFILE_RELEASE_OPT_LEVEL=z
export CARGO_PROFILE_RELEASE_PANIC=abort
export RUSTFLAGS+=" --remap-path-prefix=$CARGO_HOME/registry/="

# We don't want to use any native libraries
unset PKG_CONFIG_PATH

CURL="curl --silent --location --retry 3 --retry-max-time 30"

# Download and build dependencies from source

if [ "$DARWIN" = true ]; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --no-modify-path --profile minimal --default-toolchain nightly
  export RUSTFLAGS+=" -Zlocation-detail=none -Zfmt-debug=none"
  CFLAGS= cargo install cargo-c --locked
fi

if [ "${PLATFORM%-*}" == "linuxmusl" ] || [ "$DARWIN" = true ]; then
  mkdir ${DEPS}/proxy-libintl
  $CURL https://github.com/frida/proxy-libintl/archive/${VERSION_PROXY_LIBINTL}.tar.gz | tar xzC ${DEPS}/proxy-libintl --strip-components=1
  cd ${DEPS}/proxy-libintl
  meson setup _build --default-library=static --buildtype=release --strip --prefix=${TARGET} ${MESON}
  meson install -C _build --tag devel
fi

# zlib-ng
mkdir ${DEPS}/zlib-ng
$CURL https://github.com/zlib-ng/zlib-ng/archive/${VERSION_ZLIB_NG}.tar.gz | tar xzC ${DEPS}/zlib-ng --strip-components=1
cd ${DEPS}/zlib-ng
CFLAGS="${CFLAGS} -O3" cmake -G"Unix Makefiles" \
  -DCMAKE_TOOLCHAIN_FILE=${ROOT}/Toolchain.cmake -DCMAKE_INSTALL_PREFIX=${TARGET} -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=FALSE -DBUILD_TESTING=FALSE -DZLIB_COMPAT=TRUE -DWITH_ARMV6=FALSE
make install/strip

# libffi
mkdir ${DEPS}/ffi
$CURL https://github.com/libffi/libffi/releases/download/v${VERSION_FFI}/libffi-${VERSION_FFI}.tar.gz | tar xzC ${DEPS}/ffi --strip-components=1
cd ${DEPS}/ffi
./configure --host=${CHOST} --prefix=${TARGET} --enable-static --disable-shared --disable-dependency-tracking \
  --disable-builddir --disable-multi-os-directory --disable-raw-api --disable-structs --disable-docs
make install-strip

# glib
mkdir ${DEPS}/glib
$CURL https://download.gnome.org/sources/glib/$(without_patch $VERSION_GLIB)/glib-${VERSION_GLIB}.tar.xz | tar xJC ${DEPS}/glib --strip-components=1
cd ${DEPS}/glib
$CURL https://gist.github.com/kleisauke/284d685efa00908da99ea6afbaaf39ae/raw/bdad5489a61c217850631571caf57f5db6ea8b2c/glib-without-gregex.patch | patch -p1
meson setup _build --default-library=static --buildtype=release --strip --prefix=${TARGET} --datadir=${TARGET}/share ${MESON} \
  --force-fallback-for=gvdb -Dintrospection=disabled -Dnls=disabled -Dlibmount=disabled -Dsysprof=disabled -Dlibelf=disabled \
  -Dtests=false -Dglib_assert=false -Dglib_checks=false -Dglib_debug=disabled ${DARWIN:+-Dbsymbolic_functions=false}
meson install -C _build --tag bin-devel,devel

# libxml2
mkdir ${DEPS}/xml2
$CURL https://download.gnome.org/sources/libxml2/$(without_patch $VERSION_XML2)/libxml2-${VERSION_XML2}.tar.xz | tar xJC ${DEPS}/xml2 --strip-components=1
cd ${DEPS}/xml2
meson setup _build --default-library=static --buildtype=release --strip --prefix=${TARGET} ${MESON} \
  -Dminimum=true
meson install -C _build --tag devel

# libexif
mkdir ${DEPS}/exif
$CURL https://github.com/libexif/libexif/releases/download/v${VERSION_EXIF}/libexif-${VERSION_EXIF}.tar.xz | tar xJC ${DEPS}/exif --strip-components=1
cd ${DEPS}/exif
./configure --host=${CHOST} --prefix=${TARGET} --enable-static --disable-shared --disable-dependency-tracking \
  --disable-nls --disable-docs --without-libiconv-prefix --without-libintl-prefix \
  CPPFLAGS="${CPPFLAGS} -DNO_VERBOSE_TAG_DATA"
make install-strip doc_DATA=

# lcms2
mkdir ${DEPS}/lcms
$CURL https://github.com/mm2/Little-CMS/releases/download/lcms${VERSION_LCMS}/lcms2-${VERSION_LCMS}.tar.gz | tar xzC ${DEPS}/lcms --strip-components=1
cd ${DEPS}/lcms
CFLAGS="${CFLAGS} -O3" meson setup _build --default-library=static --buildtype=release --strip --prefix=${TARGET} ${MESON} \
  -Dtests=disabled
meson install -C _build --tag devel

# aom (AV1)
mkdir ${DEPS}/aom
$CURL https://storage.googleapis.com/aom-releases/libaom-${VERSION_AOM}.tar.gz | tar xzC ${DEPS}/aom --strip-components=1
cd ${DEPS}/aom
mkdir aom_build && cd aom_build
AOM_AS_FLAGS="${FLAGS}" cmake -G"Unix Makefiles" \
  -DCMAKE_TOOLCHAIN_FILE=${ROOT}/Toolchain.cmake -DCMAKE_INSTALL_PREFIX=${TARGET} -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_BUILD_TYPE=MinSizeRel \
  -DBUILD_SHARED_LIBS=FALSE -DENABLE_DOCS=0 -DENABLE_TESTS=0 -DENABLE_TESTDATA=0 -DENABLE_TOOLS=0 -DENABLE_EXAMPLES=0 \
  -DCONFIG_PIC=1 -DENABLE_NASM=1 ${WITHOUT_NEON:+-DENABLE_NEON=0} -DENABLE_RVV=0 \
  -DCONFIG_AV1_HIGHBITDEPTH=0 -DCONFIG_WEBM_IO=0 \
  ..
make install/strip

# libheif
mkdir ${DEPS}/heif
$CURL https://github.com/strukturag/libheif/archive/${VERSION_HEIF}.tar.gz | tar xzC ${DEPS}/heif --strip-components=1
cd ${DEPS}/heif
CFLAGS="${CFLAGS} -O3" CXXFLAGS="${CXXFLAGS} -O3" cmake -G"Unix Makefiles" \
  -DCMAKE_TOOLCHAIN_FILE=${ROOT}/Toolchain.cmake -DCMAKE_INSTALL_PREFIX=${TARGET} -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=FALSE -DBUILD_DOCUMENTATION=0 -DBUILD_TESTING=0 -DENABLE_PLUGIN_LOADING=0 -DWITH_EXAMPLES=0 -DWITH_LIBDE265=0 -DWITH_X265=0
make install/strip

# mozjpeg
mkdir ${DEPS}/jpeg
$CURL https://github.com/mozilla/mozjpeg/archive/${VERSION_MOZJPEG}.tar.gz | tar xzC ${DEPS}/jpeg --strip-components=1
cd ${DEPS}/jpeg
$CURL https://github.com/mozilla/mozjpeg/commit/f90668e0e4fb79c81e1f24a0ccc0e2090af761bf.patch | patch -p1
sed -i'.bak' 's/JCP_MAX_COMPRESSION/JCP_FASTEST/' jcapimin.c
cmake -G"Unix Makefiles" \
  -DCMAKE_TOOLCHAIN_FILE=${ROOT}/Toolchain.cmake -DCMAKE_INSTALL_PREFIX=${TARGET} -DCMAKE_INSTALL_LIBDIR:PATH=lib -DCMAKE_BUILD_TYPE=MinSizeRel \
  -DBUILD_SHARED_LIBS=FALSE -DWITH_JPEG8=1 -DWITH_TURBOJPEG=FALSE -DPNG_SUPPORTED=FALSE
make install/strip

# libpng
mkdir ${DEPS}/png
$CURL https://github.com/pnggroup/libpng/archive/v${VERSION_PNG}.tar.gz | tar xzC ${DEPS}/png --strip-components=1
cd ${DEPS}/png
./configure --host=${CHOST} --prefix=${TARGET} --enable-static --disable-shared --disable-dependency-tracking \
  --disable-tools --without-binconfigs --disable-unversioned-libpng-config
make install-strip dist_man_MANS=

# libimagequant
mkdir ${DEPS}/imagequant
$CURL https://github.com/lovell/libimagequant/archive/v${VERSION_IMAGEQUANT}.tar.gz | tar xzC ${DEPS}/imagequant --strip-components=1
cd ${DEPS}/imagequant
CFLAGS="${CFLAGS} -O3" meson setup _build --default-library=static --buildtype=release --strip --prefix=${TARGET} ${MESON}
meson install -C _build --tag devel

# libwebp
mkdir ${DEPS}/webp
$CURL https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-${VERSION_WEBP}.tar.gz | tar xzC ${DEPS}/webp --strip-components=1
cd ${DEPS}/webp
./configure --host=${CHOST} --prefix=${TARGET} --enable-static --disable-shared --disable-dependency-tracking \
  --enable-libwebpmux --enable-libwebpdemux ${WITHOUT_NEON:+--disable-neon}
make install-strip bin_PROGRAMS= noinst_PROGRAMS= man_MANS=

# libtiff
mkdir ${DEPS}/tiff
$CURL https://gitlab.com/libtiff/libtiff/-/archive/${VERSION_TIFF}/libtiff-${VERSION_TIFF}.tar.gz | tar xzC ${DEPS}/tiff --strip-components=1
cd ${DEPS}/tiff
cmake -G"Unix Makefiles" \
  -DCMAKE_TOOLCHAIN_FILE=${ROOT}/Toolchain.cmake -DCMAKE_INSTALL_PREFIX=${TARGET} -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_BUILD_TYPE=MinSizeRel \
  -DBUILD_SHARED_LIBS=FALSE -DCMath_HAVE_LIBC_POW=1 \
  -Dtiff-contrib=OFF -Dtiff-cxx=OFF -Dtiff-docs=OFF -Dtiff-tests=OFF -Dtiff-tools=OFF -Dmdi=OFF \
  -Djbig=OFF -Dlerc=OFF -Dlibdeflate=OFF -Dlzma=OFF -Dold-jpeg=OFF -Dpixarlog=OFF -Dtiff-opengl=OFF -Dzstd=OFF
make install/strip

# highway
if [ -z "$WITHOUT_HIGHWAY" ]; then
  mkdir ${DEPS}/highway
  $CURL https://github.com/google/highway/archive/${VERSION_HIGHWAY}.tar.gz | tar xzC ${DEPS}/highway --strip-components=1
  cd ${DEPS}/highway
  CFLAGS="${CFLAGS} -O3" CXXFLAGS="${CXXFLAGS} -O3" cmake -G"Unix Makefiles" \
    -DCMAKE_TOOLCHAIN_FILE=${ROOT}/Toolchain.cmake -DCMAKE_INSTALL_PREFIX=${TARGET} -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=FALSE -DBUILD_TESTING=0 -DHWY_ENABLE_CONTRIB=0 -DHWY_ENABLE_EXAMPLES=0 -DHWY_ENABLE_TESTS=0
  make install/strip
fi

# freetype
build_freetype() {
  rm -rf ${DEPS}/freetype
  mkdir ${DEPS}/freetype
  $CURL https://github.com/freetype/freetype/archive/VER-${VERSION_FREETYPE//./-}.tar.gz | tar xzC ${DEPS}/freetype --strip-components=1
  cd ${DEPS}/freetype
  meson setup _build --default-library=static --buildtype=release --strip --prefix=${TARGET} ${MESON} \
    -Dzlib=enabled -Dpng=enabled -Dbrotli=disabled -Dbzip2=disabled "$@"
  meson install -C _build --tag devel
}
build_freetype -Dharfbuzz=disabled

# expat
mkdir ${DEPS}/expat
$CURL https://github.com/libexpat/libexpat/releases/download/R_${VERSION_EXPAT//./_}/expat-${VERSION_EXPAT}.tar.xz | tar xJC ${DEPS}/expat --strip-components=1
cd ${DEPS}/expat
./configure --host=${CHOST} --prefix=${TARGET} --enable-static --disable-shared \
  --disable-dependency-tracking --without-xmlwf --without-docbook --without-getrandom --without-sys-getrandom \
  --without-libbsd --without-examples --without-tests
make install-strip dist_cmake_DATA= nodist_cmake_DATA=

# libarchive
mkdir ${DEPS}/archive
$CURL https://github.com/libarchive/libarchive/releases/download/v${VERSION_ARCHIVE}/libarchive-${VERSION_ARCHIVE}.tar.xz | tar xJC ${DEPS}/archive --strip-components=1
cd ${DEPS}/archive
./configure --host=${CHOST} --prefix=${TARGET} --enable-static --disable-shared --disable-dependency-tracking \
  --disable-bsdtar --disable-bsdcat --disable-bsdcpio --disable-bsdunzip --disable-posix-regex-lib --disable-xattr --disable-acl \
  --without-bz2lib --without-libb2 --without-iconv --without-lz4 --without-zstd --without-lzma \
  --without-lzo2 --without-cng --without-openssl --without-xml2 --without-expat
make install-strip libarchive_man_MANS=

# fontconfig
mkdir ${DEPS}/fontconfig
$CURL https://gitlab.freedesktop.org/fontconfig/fontconfig/-/archive/${VERSION_FONTCONFIG}/fontconfig-${VERSION_FONTCONFIG}.tar.gz | tar xzC ${DEPS}/fontconfig --strip-components=1
cd ${DEPS}/fontconfig
sed -i'.bak' "/subdir('its')/d" meson.build
sed -i'.bak' "/using without calling FcInit/d" src/fcobjs.c
meson setup _build --default-library=static --buildtype=release --strip --prefix=${TARGET} ${MESON} \
  -Dcache-build=disabled -Ddoc=disabled -Dnls=disabled -Dtests=disabled -Dtools=disabled
meson install -C _build --tag devel

# harfbuzz
mkdir ${DEPS}/harfbuzz
$CURL https://github.com/harfbuzz/harfbuzz/archive/${VERSION_HARFBUZZ}.tar.gz | tar xzC ${DEPS}/harfbuzz --strip-components=1
cd ${DEPS}/harfbuzz
meson setup _build --default-library=static --buildtype=release --strip --prefix=${TARGET} ${MESON} \
  -Dgobject=disabled -Dicu=disabled -Dtests=disabled -Dintrospection=disabled -Ddocs=disabled -Dbenchmark=disabled -Dutilities=disabled \
  -Draster=disabled -Dvector=disabled -Dsubset=disabled -Dgpu=disabled -Dgpu_demo=disabled \
  ${DARWIN:+-Dcoretext=enabled}
meson install -C _build --tag devel

build_freetype -Dharfbuzz=enabled

# pixman
mkdir ${DEPS}/pixman
$CURL https://cairographics.org/releases/pixman-${VERSION_PIXMAN}.tar.gz | tar xzC ${DEPS}/pixman --strip-components=1
cd ${DEPS}/pixman
meson setup _build --default-library=static --buildtype=release --strip --prefix=${TARGET} ${MESON} \
  -Dlibpng=disabled -Dgtk=disabled -Dopenmp=disabled -Dtests=disabled -Ddemos=disabled \
  ${WITHOUT_NEON:+-Da64-neon=disabled}
meson install -C _build --tag devel

# cairo
mkdir ${DEPS}/cairo
$CURL https://cairographics.org/releases/cairo-${VERSION_CAIRO}.tar.xz | tar xJC ${DEPS}/cairo --strip-components=1
cd ${DEPS}/cairo
meson setup _build --default-library=static --buildtype=release --strip --prefix=${TARGET} ${MESON} \
  ${LINUX:+-Dquartz=disabled} ${DARWIN:+-Dquartz=enabled} -Dfreetype=enabled -Dfontconfig=enabled -Dtee=disabled -Dxcb=disabled -Dxlib=disabled -Dzlib=disabled \
  -Dtests=disabled -Dspectre=disabled -Dsymbol-lookup=disabled
meson install -C _build --tag devel

# fribidi
mkdir ${DEPS}/fribidi
$CURL https://github.com/fribidi/fribidi/releases/download/v${VERSION_FRIBIDI}/fribidi-${VERSION_FRIBIDI}.tar.xz | tar xJC ${DEPS}/fribidi --strip-components=1
cd ${DEPS}/fribidi
meson setup _build --default-library=static --buildtype=release --strip --prefix=${TARGET} ${MESON} \
  -Ddocs=false -Dbin=false -Dtests=false
meson install -C _build --tag devel

# pango
mkdir ${DEPS}/pango
$CURL https://download.gnome.org/sources/pango/$(without_patch $VERSION_PANGO)/pango-${VERSION_PANGO}.tar.xz | tar xJC ${DEPS}/pango --strip-components=1
cd ${DEPS}/pango
sed -i'.bak' "/subdir('utils')/{N;d;}" meson.build
meson setup _build --default-library=static --buildtype=release --strip --prefix=${TARGET} ${MESON} \
  -Ddocumentation=false -Dbuild-testsuite=false -Dbuild-examples=false -Dintrospection=disabled -Dfontconfig=enabled
meson install -C _build --tag devel

# librsvg
mkdir ${DEPS}/rsvg
$CURL https://download.gnome.org/sources/librsvg/$(without_patch $VERSION_RSVG)/librsvg-${VERSION_RSVG}.tar.xz | tar xJC ${DEPS}/rsvg --strip-components=1
cd ${DEPS}/rsvg
sed -i'.bak' "/image = /s/, \"gif\", \"webp\"//" rsvg/Cargo.toml
sed -i'.bak' "/cairo-rs = /s/, \"pdf\", \"ps\"//" {librsvg-c,rsvg}/Cargo.toml
sed -i'.bak' "/^if host_system in \['windows'/s/, 'linux'//" meson.build
cargo update --workspace
PKG_CONFIG=${PKG_CONFIG/ --static/} meson setup _build --default-library=static --buildtype=plain --strip --prefix=${TARGET} ${MESON} \
  -Dintrospection=disabled -Dpixbuf{,-loader}=disabled -Drsvg-convert=disabled -Ddocs=disabled -Dvala=disabled -Dtests=false \
  ${RUST_TARGET:+-Dtriplet=$RUST_TARGET}
meson install -C _build --tag devel

# cgif
mkdir ${DEPS}/cgif
$CURL https://github.com/dloebl/cgif/archive/v${VERSION_CGIF}.tar.gz | tar xzC ${DEPS}/cgif --strip-components=1
cd ${DEPS}/cgif
CFLAGS="${CFLAGS} -O3" meson setup _build --default-library=static --buildtype=release --strip --prefix=${TARGET} ${MESON} \
  -Dexamples=false -Dtests=false
meson install -C _build --tag devel

# libultrahdr
mkdir ${DEPS}/uhdr
$CURL https://github.com/google/libultrahdr/archive/${VERSION_UHDR}.tar.gz | tar xzC ${DEPS}/uhdr --strip-components=1
cd ${DEPS}/uhdr
$CURL https://patch-diff.githubusercontent.com/raw/google/libultrahdr/pull/383.patch | patch -p1
sed -i'.bak' 's/CMAKE_CROSSCOMPILING AND UHDR_ENABLE_INSTALL/FALSE/' CMakeLists.txt
CFLAGS="${CFLAGS} -O3" CXXFLAGS="${CXXFLAGS} -O3" cmake -G"Unix Makefiles" \
  -DCMAKE_TOOLCHAIN_FILE=${ROOT}/Toolchain.cmake -DCMAKE_INSTALL_PREFIX=${TARGET} -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=FALSE -DUHDR_BUILD_EXAMPLES=FALSE -DUHDR_MAX_DIMENSION=65500 ${WITHOUT_NEON:+-DUHDR_ENABLE_INTRINSICS=FALSE}
make install/strip

# libvips itself
mkdir ${DEPS}/vips
$CURL https://github.com/libvips/libvips/releases/download/v${VERSION_VIPS}/vips-${VERSION_VIPS}.tar.xz | tar xJC ${DEPS}/vips --strip-components=1
cd ${DEPS}/vips
$CURL https://gist.githubusercontent.com/lovell/313a6901e9db1bf285f2a1f1180499e4/raw/3988223c7dfa4d22745d9392034b0117abef1446/libvips-cpp-soversion.patch | patch -p1
$CURL https://raw.githubusercontent.com/libvips/build-win64-mxe/v${VERSION_VIPS}/build/patches/vips-8-heifsave-disable-hbr-support.patch | patch -p1
sed -i'.bak' "s/library('vips'/static_&/" libvips/meson.build
sed -i'.bak' "/version: library_version/{N;d;}" libvips/meson.build
if [ "$LINUX" = true ]; then
  sed -i'.bak' "/gnu_symbol_visibility: 'hidden',/a link_args: nodelete_link_args," cplusplus/meson.build
  EXCLUDE_LIBS=$(find ${TARGET}/lib -maxdepth 1 -name '*.a' ! -name 'libglib-2.0.a' ! -name 'libgobject-2.0.a' -printf "-Wl,--exclude-libs=%f ")
  EXCLUDE_LIBS=${EXCLUDE_LIBS%?}
  printf "{local:g_param_spec_types;};" > vips.map
fi
sed -i'.bak' "/subdir('man')/{N;N;N;N;d;}" meson.build
CFLAGS="${CFLAGS} -O3" CXXFLAGS="${CXXFLAGS} -O3" meson setup _build --default-library=shared --buildtype=release --strip --prefix=${TARGET} ${MESON} \
  -Ddeprecated=false -Dexamples=false -Dauto_features=enabled -Dintrospection=disabled -Dmodules=disabled -Dcfitsio=disabled -Dfftw=disabled \
  -Djpeg-xl=disabled ${WITHOUT_HIGHWAY:+-Dhighway=disabled} -Dorc=disabled -Dmagick=disabled -Dmatio=disabled -Dnifti=disabled -Dopenexr=disabled \
  -Dopenjpeg=disabled -Dopenslide=disabled -Dpdfium=disabled -Dpoppler=disabled -Dquantizr=disabled -Draw=disabled -Dspng=disabled \
  -Dppm=false -Danalyze=false -Dradiance=false \
  ${LINUX:+-Dcpp_link_args="$LDFLAGS -Wl,-Bsymbolic-functions -Wl,--version-script=$DEPS/vips/vips.map $EXCLUDE_LIBS"}
meson install -C _build --tag runtime,devel

# Cleanup
rm -rf ${TARGET}/lib/{pkgconfig,.libs,*.la,cmake}

mkdir ${TARGET}/lib-filtered
mv ${TARGET}/lib/glib-2.0 ${TARGET}/lib-filtered

# Pack only relevant libraries
function copydeps {
  local base=$1
  local dest_dir=$2

  cp -L $base $dest_dir/$base
  chmod 644 $dest_dir/$base

  if [ "$LINUX" = true ]; then
    local dependencies=$(readelf -d $base | grep NEEDED | awk '{ print $5 }' | tr -d '[]')
  elif [ "$DARWIN" = true ]; then
    local dependencies=$(otool -LX $base | awk '{print $1}' | grep $TARGET)
    install_name_tool -id @rpath/$base $dest_dir/$base
  fi

  for dep in $dependencies; do
    base_dep=$(basename $dep)
    [ ! -f "$PWD/$base_dep" ] && echo "$base_dep does not exist in $PWD" && continue
    echo "$base depends on $base_dep"

    if [ ! -f "$dest_dir/$base_dep" ]; then
      if [ "$DARWIN" = true ]; then
        install_name_tool -change $dep @rpath/$base_dep $dest_dir/$base
      fi
      copydeps $base_dep $dest_dir
    fi
  done
}

cd ${TARGET}/lib
if [ "$LINUX" = true ]; then
  readelf -Wd ${VIPS_CPP_DEP} | grep -qF NODELETE || (echo "$VIPS_CPP_DEP was not linked with -z nodelete" && exit 1)
  readelf -Ws ${VIPS_CPP_DEP} | c++filt | grep -qF "::__cxx11::" || (echo "$VIPS_CPP_DEP mistakenly uses the C++03 ABI" && exit 1)
fi
copydeps ${VIPS_CPP_DEP} ${TARGET}/lib-filtered

# Create JSON file of version numbers
cd ${TARGET}
printf "{\n\
  \"aom\": \"${VERSION_AOM}\",\n\
  \"archive\": \"${VERSION_ARCHIVE}\",\n\
  \"cairo\": \"${VERSION_CAIRO}\",\n\
  \"cgif\": \"${VERSION_CGIF}\",\n\
  \"exif\": \"${VERSION_EXIF}\",\n\
  \"expat\": \"${VERSION_EXPAT}\",\n\
  \"ffi\": \"${VERSION_FFI}\",\n\
  \"fontconfig\": \"${VERSION_FONTCONFIG}\",\n\
  \"freetype\": \"${VERSION_FREETYPE}\",\n\
  \"fribidi\": \"${VERSION_FRIBIDI}\",\n\
  \"glib\": \"${VERSION_GLIB}\",\n\
  \"harfbuzz\": \"${VERSION_HARFBUZZ}\",\n\
  \"heif\": \"${VERSION_HEIF}\",\n\
  \"highway\": \"${VERSION_HIGHWAY}\",\n\
  \"imagequant\": \"${VERSION_IMAGEQUANT}\",\n\
  \"lcms\": \"${VERSION_LCMS}\",\n\
  \"mozjpeg\": \"${VERSION_MOZJPEG}\",\n\
  \"pango\": \"${VERSION_PANGO}\",\n\
  \"pixman\": \"${VERSION_PIXMAN}\",\n\
  \"png\": \"${VERSION_PNG}\",\n\
  \"proxy-libintl\": \"${VERSION_PROXY_LIBINTL}\",\n\
  \"rsvg\": \"${VERSION_RSVG}\",\n\
  \"tiff\": \"${VERSION_TIFF}\",\n\
  \"uhdr\": \"${VERSION_UHDR}\",\n\
  \"vips\": \"${VERSION_VIPS}\",\n\
  \"webp\": \"${VERSION_WEBP}\",\n\
  \"xml2\": \"${VERSION_XML2}\",\n\
  \"zlib-ng\": \"${VERSION_ZLIB_NG}\"\n\
}" >versions.json

# Create tarball
ls -al lib
rm -rf lib
mv lib-filtered lib
tar chzf ${PACKAGE}/libvips-${PLATFORM}.tar.gz \
  include \
  lib \
  *.json

chmod 644 ${PACKAGE}/libvips-${PLATFORM}.tar.*
