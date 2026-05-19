#!/usr/bin/env bash
set -e

source ./versions.properties

CURL="curl --silent --location --retry 3 --retry-max-time 30"

ALL_AT_VERSION_LATEST=true
UPDATES=()

version_latest() {
  local name=$1
  local current=$2
  local source=$3  # release-monitoring project ID or GitHub org/repo
  local selector=${4:-"stable_versions"}

  local latest=""
  if [[ "$source" == *"/"* ]]; then
    latest=$(git -c 'versionsort.suffix=-' ls-remote --tags --refs --sort='v:refname' "https://github.com/$source.git" | awk -F'/' 'END{print $3}' | tr -d 'v')
  else
    latest=$($CURL "https://release-monitoring.org/api/v2/versions/?project_id=$source" | jq -j ".$selector[0]" | tr '_' '.')
  fi

  if [ -n "$latest" ] && [ "$latest" != "$current" ]; then
    ALL_AT_VERSION_LATEST=false
    local var="VERSION_$(echo "$name" | tr '[:lower:]-' '[:upper:]_')"
    sed -i.bak "s/^$var=.*/$var=$latest/" versions.properties
    UPDATES+=("$name ($current → $latest)")
  fi
  sleep 1
}

version_latest "aom" "$VERSION_AOM" "17628"
version_latest "archive" "$VERSION_ARCHIVE" "libarchive/libarchive"
version_latest "cairo" "$VERSION_CAIRO" "247"
version_latest "cgif" "$VERSION_CGIF" "dloebl/cgif"
version_latest "exif" "$VERSION_EXIF" "libexif/libexif"
version_latest "expat" "$VERSION_EXPAT" "770"
version_latest "ffi" "$VERSION_FFI" "1611"
version_latest "fontconfig" "$VERSION_FONTCONFIG" "827"
version_latest "freetype" "$VERSION_FREETYPE" "854"
version_latest "fribidi" "$VERSION_FRIBIDI" "fribidi/fribidi"
version_latest "glib" "$VERSION_GLIB" "10024" "unstable"
version_latest "harfbuzz" "$VERSION_HARFBUZZ" "1299"
version_latest "highway" "$VERSION_HIGHWAY" "205809"
version_latest "lcms" "$VERSION_LCMS" "9815"
version_latest "pango" "$VERSION_PANGO" "11783" "unstable"
version_latest "pixman" "$VERSION_PIXMAN" "3648"
version_latest "png" "$VERSION_PNG" "1705"
version_latest "proxy-libintl" "$VERSION_PROXY_LIBINTL" "frida/proxy-libintl"
version_latest "rsvg" "$VERSION_RSVG" "5420" "unstable"
version_latest "webp" "$VERSION_WEBP" "1761"
version_latest "xml2" "$VERSION_XML2" "1783"
version_latest "zlib-ng" "$VERSION_ZLIB_NG" "115592"

if [ "$ALL_AT_VERSION_LATEST" = "false" ]; then
  echo "Dependency updates applied:"
  printf '  %s\n' "${UPDATES[@]}"
else
  echo "All dependencies at latest versions."
fi
