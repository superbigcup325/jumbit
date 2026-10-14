#!/usr/bin/env bash
# jumbit one-line install: download the prebuilt binary from a GitHub Release into the user bin directory
#
# Usage:
#   curl -fsSL https://github.com/superbigcup325/jumbit/releases/latest/download/install.sh | sh
#   ./install.sh [version]                             # a positional argument pins the version (v prefix optional)
#   JUMBIT_VERSION=0.1.3 ./install.sh                  # pin the version by env var; defaults to latest
#   JUMBIT_INSTALL_DIR=/usr/local/bin ./install.sh     # another install directory; defaults to ~/.local/bin
#
# Platform coverage matches release.yml's matrix: linux-x86_64 /
# macos-aarch64; Windows x64 does not use this script (grab the zip from Releases). POSIX sh
# compatible (curl | sh works under dash); needs curl and tar
set -eu

repo=superbigcup325/jumbit
install_dir=${JUMBIT_INSTALL_DIR:-"$HOME/.local/bin"}

case "$(uname -s)/$(uname -m)" in
  Linux/x86_64) target=linux-x86_64 ;;
  Darwin/arm64) target=macos-aarch64 ;;
  MINGW* | MSYS* | CYGWIN* | Windows*)
    echo "✗ Windows does not use this script: download the windows-x86_64 zip from https://github.com/$repo/releases" >&2
    exit 1 ;;
  *)
    echo "✗ no prebuilt artefact for $(uname -s)/$(uname -m) (available: Linux x86_64 / macOS Apple Silicon / Windows x64)" >&2
    exit 1 ;;
esac

version=${1:-${JUMBIT_VERSION:-}}
if [ -z "$version" ]; then
  # the 302 target of releases/latest is the tag page; its last segment is the version, no API or jq needed
  version=$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/$repo/releases/latest")
  version=${version##*/}
fi
version=${version#v}
case "$version" in
  *[!0-9.]*) echo "✗ cannot parse the version: $version" >&2; exit 1 ;;
esac

url="https://github.com/$repo/releases/download/v$version/jumbit-$version-$target.tar.gz"
echo "==> downloading $url"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "$url" -o "$tmp/pkg.tar.gz"
tar -xzf "$tmp/pkg.tar.gz" -C "$tmp"
bin="$tmp/jumbit-$version-$target"
[ -f "$bin" ] || { echo "✗ unexpected archive contents: jumbit-$version-$target is missing" >&2; exit 1; }

mkdir -p "$install_dir"
mv "$bin" "$install_dir/jumbit"
chmod 755 "$install_dir/jumbit"
echo "==> installed $install_dir/jumbit (v$version)"

case ":$PATH:" in
  *":$install_dir:"*) ;;
  *)
    echo "==> $install_dir is not on PATH; add it to your shell config and reopen the terminal:" >&2
    echo "    export PATH=\"$install_dir:\$PATH\"" >&2 ;;
esac
echo "==> next: eval \"\$(jumbit init bash)\" (zsh/fish and friends: see the README Quick start)"
