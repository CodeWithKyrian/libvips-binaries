FROM --platform=linux/arm64 rockylinux:8

ENV \
  RUSTUP_HOME="/usr/local/rustup" \
  CARGO_HOME="/usr/local/cargo" \
  PATH="/usr/local/cargo/bin:/opt/rh/gcc-toolset-15/root/usr/bin:$PATH"

RUN \
  dnf update -y && \
  dnf install -y epel-release && \
  dnf config-manager --set-enabled powertools && \
  dnf install -y --setopt=tsflags=nodocs \
    autoconf automake bzip2 cmake curl-devel findutils gcc-toolset-15-gcc gcc-toolset-15-gcc-c++ \
    gettext git gperf jq make openssl-devel patch pkgconf python3.12-pip tar xz \
    && \
  curl https://sh.rustup.rs -sSf | sh -s -- -y \
    --no-modify-path --profile minimal --default-host aarch64-unknown-linux-gnu --default-toolchain nightly \
    && \
  cargo install cargo-c --locked && \
  pip3.12 install meson ninja

ENV \
  PKG_CONFIG="aarch64-linux-gnu-pkgconf --static" \
  PLATFORM="linux-arm64v8" \
  FLAGS="-march=armv8-a" \
  RUSTFLAGS="-Zlocation-detail=none -Zfmt-debug=none" \
  MESON="--cross-file=/root/meson.ini"

COPY Toolchain.cmake /root/
COPY meson.ini /root/
COPY aarch64-linux-gnu-pkgconf /usr/bin
