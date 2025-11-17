#!/usr/bin/env bash

set -euo pipefail

GH_REPO="https://github.com/peco/peco"
TOOL_NAME="peco"
TOOL_TEST="peco --version"

fail() {
  echo "asdf-${TOOL_NAME}: $*"
  exit 1
}

curl_opts=(-fsSL)

if [ -n "${GITHUB_API_TOKEN:-}" ]; then
  curl_opts=("${curl_opts[@]}" -H "Authorization: token $GITHUB_API_TOKEN")
fi

sort_versions() {
  sed 'h; s/[+-]/./g; s/.p\([[:digit:]]\)/.z\1/; s/$/.z/; G; s/\n/ /' |
    LC_ALL=C sort -t. -k 1,1 -k 2,2n -k 3,3n -k 4,4n -k 5,5n | awk '{print $2}'
}

list_github_tags() {
  git ls-remote --tags --refs "$GH_REPO" |
    grep -o 'refs/tags/.*' | cut -d/ -f3- |
    sed 's/^v//'
}

list_all_versions() {
  list_github_tags
}

latest_version() {
  list_all_versions | sort_versions | tail -n1 | xargs echo
}

resolve_version() {
  local version="$1"

  if [ "$version" = "latest" ]; then
    version="$(latest_version)"
  fi

  echo "$version"
}

detect_platform() {
  case "$OSTYPE" in
    darwin*) echo "darwin" ;;
    linux*) echo "linux" ;;
    *) fail "Unsupported platform" ;;
  esac
}

detect_architecture() {
  case "$(uname -m)" in
    x86_64) echo "amd64" ;;
    i386 | i686) echo "386" ;;
    arm | aarch64) echo "arm" ;;
    arm64) echo "arm64" ;;
    armv5* | armv6* | armv7*) echo "arm" ;;
    *) fail "Unsupported architecture" ;;
  esac
}

release_filename() {
  local platform architecture archive_format
  platform="$(detect_platform)"
  architecture="$(detect_architecture)"

  case "$platform" in
    darwin) archive_format="zip" ;;
    linux) archive_format="tar.gz" ;;
  esac

  echo "${TOOL_NAME}_${platform}_${architecture}.${archive_format}"
}

release_url() {
  local version filename
  version="$(resolve_version "$1")"
  filename="$(release_filename)"
  echo "${GH_REPO}/releases/download/v${version}/${filename}"
}

download_release() {
  local version filename url
  version="$(resolve_version "$1")"
  filename="$2"
  url="$(release_url "$version")"

  echo "Downloading ${TOOL_NAME} release ${version}..."
  curl "${curl_opts[@]}" -o "$filename" -C - "$url" ||
    fail "Could not download ${url}"
}

install_version() {
  local install_type="$1"
  local version="$2"
  local install_path="${3%/bin}/bin"
  local resolved_version platform archive_format

  if [ "$install_type" != "version" ]; then
    fail "asdf-${TOOL_NAME} supports release installs only"
  fi

  resolved_version="$(resolve_version "$version")"
  platform="$(detect_platform)"

  case "$platform" in
    darwin) archive_format="zip" ;;
    linux) archive_format="tar.gz" ;;
  esac

  (
    mkdir -p "$install_path"

    if [ "$archive_format" = "zip" ]; then
      unzip -j "$ASDF_DOWNLOAD_PATH/$(release_filename)" -d "$install_path" >/dev/null ||
        fail "Could not extract archive"
    else
      tar zxf "$ASDF_DOWNLOAD_PATH/$(release_filename)" -C "$install_path" --strip-components=1 ||
        fail "Could not extract archive"
    fi

    local tool_cmd
    tool_cmd="$(echo "$TOOL_TEST" | cut -d' ' -f1)"
    test -x "$install_path/$tool_cmd" ||
      fail "Expected $install_path/$tool_cmd to be executable."

    echo "${TOOL_NAME} ${resolved_version} installation was successful!"
  ) || (
    rm -rf "$install_path"
    fail "An error occurred while installing ${TOOL_NAME} ${resolved_version}."
  )
}
