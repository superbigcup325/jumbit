#!/usr/bin/env bash
# jumbit 一键安装：从 GitHub Release 下载预编译二进制，装到用户 bin 目录
#
# 用法：
#   curl -fsSL https://github.com/superbigcup325/jumbit/releases/latest/download/install.sh | sh
#   ./install.sh [version]                             # 位置参数定版本（v 前缀可省）
#   JUMBIT_VERSION=0.1.3 ./install.sh                  # 环境变量定版本，缺省取 latest
#   JUMBIT_INSTALL_DIR=/usr/local/bin ./install.sh     # 换安装目录，缺省 ~/.local/bin
#
# 平台覆盖与 .github/workflows/release.yml 的 matrix 对齐：linux-x86_64 /
# macos-aarch64；Windows x64 不走本脚本（Releases 页下 zip）。POSIX sh 兼容
# （curl | sh 在 dash 下可用），依赖 curl 与 tar
set -eu

repo=superbigcup325/jumbit
install_dir=${JUMBIT_INSTALL_DIR:-"$HOME/.local/bin"}

case "$(uname -s)/$(uname -m)" in
  Linux/x86_64) target=linux-x86_64 ;;
  Darwin/arm64) target=macos-aarch64 ;;
  MINGW* | MSYS* | CYGWIN* | Windows*)
    echo "✗ Windows 不走本脚本：到 https://github.com/$repo/releases 下载 windows-x86_64 的 zip" >&2
    exit 1 ;;
  *)
    echo "✗ 暂无 $(uname -s)/$(uname -m) 的预编译产物（现有：Linux x86_64 / macOS Apple Silicon / Windows x64）" >&2
    exit 1 ;;
esac

version=${1:-${JUMBIT_VERSION:-}}
if [ -z "$version" ]; then
  # releases/latest 的 302 落点即 tag 页，取末段即版本，免 API/jq 依赖
  version=$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/$repo/releases/latest")
  version=${version##*/}
fi
version=${version#v}
case "$version" in
  *[!0-9.]*) echo "✗ 无法解析版本号：$version" >&2; exit 1 ;;
esac

url="https://github.com/$repo/releases/download/v$version/jumbit-$version-$target.tar.gz"
echo "==> 下载 $url"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "$url" -o "$tmp/pkg.tar.gz"
tar -xzf "$tmp/pkg.tar.gz" -C "$tmp"
bin="$tmp/jumbit-$version-$target"
[ -f "$bin" ] || { echo "✗ 压缩包内容异常：缺 jumbit-$version-$target" >&2; exit 1; }

mkdir -p "$install_dir"
mv "$bin" "$install_dir/jumbit"
chmod 755 "$install_dir/jumbit"
echo "==> 已安装 $install_dir/jumbit（v$version）"

case ":$PATH:" in
  *":$install_dir:"*) ;;
  *)
    echo "==> $install_dir 不在 PATH，请加入 shell 配置后重开终端：" >&2
    echo "    export PATH=\"$install_dir:\$PATH\"" >&2 ;;
esac
echo "==> 下一步：eval \"\$(jumbit init bash)\"（zsh/fish 等见 README「快速上手」）"
