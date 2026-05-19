#!/usr/bin/env bash
set -e

## Based on build/win.sh from lovell/sharp-libvips (Apache 2.0)
## Copyright 2017 Lovell Fuller and others.
## SPDX-License-Identifier: Apache-2.0

# Dependency version numbers
source /packaging/versions.properties

VERSION_VIPS_SHORT=${VERSION_VIPS%.[[:digit:]]*}

CURL="curl --silent --location --retry 3 --retry-max-time 30"

mkdir /vips
cd /vips

case ${PLATFORM} in
  *arm64)
    ARCH=arm64
    ;;
  *x64)
    ARCH=x64
    ;;
esac

FILENAME="vips-dev-${ARCH}-web-${VERSION_VIPS}-static.zip"
URL="https://github.com/libvips/build-win64-mxe/releases/download/v${VERSION_VIPS}/${FILENAME}"
echo "Downloading $URL"
$CURL -O $URL
unzip $FILENAME

cd /vips/vips-dev-${VERSION_VIPS_SHORT}
rm bin/libvips-cpp-42.dll
cp bin/*.dll lib/

echo "Creating tarball"
tar czf /packaging/libvips-${PLATFORM}.tar.gz \
  include \
  lib/glib-2.0 \
  lib/libvips.lib \
  lib/*.dll \
  *.json

chmod 644 /packaging/libvips-${PLATFORM}.tar.*
rm -rf lib include *.json
