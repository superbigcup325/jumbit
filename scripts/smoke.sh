#!/usr/bin/env bash
# 端到端冒烟：构建真实二进制，在临时数据目录跑 add → query → 错误退出码。
# regression.sh 之后的第二道集成防线。
set -euo pipefail
export PATH="$HOME/.moon/bin:$PATH"
cd "$(dirname "$0")/.."

data=$(mktemp -d)
target=$(mktemp -d)
trap 'rm -rf "$data" "$target"' EXIT

echo "== 构建发布二进制 =="
moon build --release
bin=_build/native/release/build/cmd/main/main.exe

echo "== add 目标目录 =="
_JB_DATA_DIR="$data" "$bin" add "$target"

echo "== query 应精确回显目标目录 =="
out=$(_JB_DATA_DIR="$data" "$bin" query)
if [ "$out" != "$target" ]; then
  echo "✗ query 输出 [$out] ≠ [$target]" >&2
  exit 1
fi

echo "== 未知命令应退出码 2 =="
if _JB_DATA_DIR="$data" "$bin" frobnicate 2>/dev/null; then
  echo "✗ 未知命令退出码应为 2" >&2
  exit 1
fi

echo "== 关键词查询（末组件锚定）=="
t2=$(mktemp -d "${TMPDIR:-/tmp}/foo-demo-XXXX")
trap 'rm -rf "$data" "$target" "$t2"' EXIT
_JB_DATA_DIR="$data" "$bin" add "$t2"
out=$(_JB_DATA_DIR="$data" "$bin" query foo)
if [ "$out" != "$t2" ]; then
  echo "✗ query foo 输出 [$out] ≠ [$t2]" >&2
  exit 1
fi
out2=$(_JB_DATA_DIR="$data" "$bin" query target 2>/dev/null || true)
if _JB_DATA_DIR="$data" "$bin" query nosuchkeyword 2>/dev/null; then
  echo "✗ 无匹配关键词应退出码 1" >&2
  exit 1
fi

echo "✓ smoke 全绿"
