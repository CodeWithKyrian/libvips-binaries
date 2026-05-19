#!/usr/bin/env bash
set -e

## Based on build.sh from lovell/sharp-libvips (Apache 2.0)
## Copyright 2017 Lovell Fuller and others.
## SPDX-License-Identifier: Apache-2.0

# Dependency version numbers
source ./versions.properties

if [ $# -lt 1 ]; then
  echo
  echo "Usage: $0 PLATFORM"
  echo "Build shared libraries for libvips and its dependencies"
  echo
  echo "Possible values for PLATFORM are:"
  echo "- win-x64"
  echo "- win-arm64"
  echo "- linux-x64"
  echo "- linux-arm64"
  echo "- darwin-x64"
  echo "- darwin-arm64"
  echo
  exit 1
fi
PLATFORM="$1"

# macOS
for flavour in darwin-x64 darwin-arm64; do
  if [ $PLATFORM = $flavour ] && [ "$(uname)" == "Darwin" ]; then
    echo "Building $flavour..."

    export CC="clang"
    export CXX="clang++"

    export PLATFORM

    export PKG_CONFIG="$(brew --prefix)/bin/pkg-config --static"

    if [ $PLATFORM = "darwin-arm64" ]; then
      export MACOSX_DEPLOYMENT_TARGET="11.0"
    else
      export MACOSX_DEPLOYMENT_TARGET="10.15"
    fi

    export FLAGS="-fno-stack-check"
    export FLAGS+=" -Werror=unguarded-availability-new"
    export MESON="--cross-file=$PWD/platforms/$PLATFORM/meson.ini"

    source $PWD/versions.properties
    source $PWD/build/posix.sh

    exit 0
  fi
done

# Is docker available?
if ! [ -x "$(command -v docker)" ]; then
  echo "Please install docker"
  exit 1
fi

# Windows
for flavour in win-x64 win-arm64; do
  if [ $PLATFORM = $flavour ]; then
    echo "Building $flavour..."
    docker build --pull -t vips-dev-win32 platforms/win32
    docker run --rm -e "PLATFORM=${flavour}" -v $PWD:/packaging vips-dev-win32 sh -c "/packaging/build/win.sh"
  fi
done

# Linux
for flavour in linux-x64 linux-arm64; do
  if [ $PLATFORM = $flavour ]; then
    echo "Building $flavour..."
    docker build --pull -t "vips-dev-$flavour" "platforms/$flavour"
    docker run --rm -v $PWD:/packaging "vips-dev-$flavour" sh -c "/packaging/build/posix.sh"
  fi
done
