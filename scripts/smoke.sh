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

echo "== init 模板语法校验（参数矩阵抽样）=="
for shell in bash zsh fish; do
  if ! command -v "$shell" >/dev/null; then
    echo "  跳过 $shell（未安装）"
    continue
  fi
  for args in "" "--no-cmd" "--cmd cd" "--hook prompt" "--hook pwd --cmd j"; do
    if [ "$shell" = "bash" ]; then
      _JB_ECHO=1 _JB_RESOLVE_SYMLINKS=1 "$bin" init bash $args | bash -n || { echo "✗ bash -n 失败: $args" >&2; exit 1; }
    elif [ "$shell" = "zsh" ]; then
      _JB_ECHO=1 "$bin" init zsh $args | zsh -n || { echo "✗ zsh -n 失败: $args" >&2; exit 1; }
    else
      _JB_RESOLVE_SYMLINKS=1 "$bin" init fish $args | fish -n || { echo "✗ fish -n 失败: $args" >&2; exit 1; }
    fi
  done
done

echo "== init bash source 实测 =="
eval "$("$bin" init bash --cmd j)" 
type __jumbit_z >/dev/null && type __jumbit_zi >/dev/null && type j >/dev/null || {
  echo "✗ source 后函数未定义" >&2
  exit 1
}

echo "== remove 后 query 无结果 =="
_JB_DATA_DIR="$data" "$bin" remove -- "$target"
if _JB_DATA_DIR="$data" "$bin" query 2>/dev/null; then
  echo "✗ remove 后 query 应无结果（退出码 1）" >&2
  exit 1
fi
# 重新 add 供后续段落使用
_JB_DATA_DIR="$data" "$bin" add -- "$target"

echo "== --list --score 输出格式（6.1f 得分前缀 + 空格 + 路径）=="
out=$(_JB_DATA_DIR="$data" "$bin" query --list --score)
if [ "$(echo "$out" | wc -l)" -lt 1 ]; then
  echo "✗ --list 无输出" >&2
  exit 1
fi
if ! echo "$out" | grep -qE '^ *[0-9]+\.[0-9] .*tmp'; then
  echo "✗ --score 前缀格式不符: $out" >&2
  exit 1
fi

echo "== query --json：单行 JSON 数组（agent 通道）=="
jdata=$(mktemp -d "${TMPDIR:-/tmp}/jumbit-json-XXXX")
printf '/smoke-json|1|1704067200\n' > "$jdata/z.txt"
_JB_DATA_DIR="$jdata" _Z_DATA="$jdata/z.txt" "$bin" import z >/dev/null 2>&1
json_out=$(_JB_DATA_DIR="$jdata" "$bin" query --json --all)
expected='[{"path":"/smoke-json","score":0.25,"last_accessed":1704067200,"matched_by":"exact"}]'
if [ "$json_out" != "$expected" ]; then
  echo "✗ --json 输出不符: [$json_out]" >&2
  exit 1
fi
rm -rf "$jdata"

echo "== 未知命令应退出码 2 =="
if _JB_DATA_DIR="$data" "$bin" frobnicate 2>/dev/null; then
  echo "✗ 未知命令退出码应为 2" >&2
  exit 1
fi

echo "== 关键词查询（末组件锚定）=="
t2=$(mktemp -d "${TMPDIR:-/tmp}/foo-demo-XXXX")
trap 'rm -rf "$data" "$target" "$t2"' EXIT
_JB_DATA_DIR="$data" "$bin" add -- "$t2"
out=$(_JB_DATA_DIR="$data" "$bin" query foo)
if [ "$out" != "$t2" ]; then
  echo "✗ query foo 输出 [$out] ≠ [$t2]" >&2
  exit 1
fi
if _JB_DATA_DIR="$data" "$bin" query nosuchkeyword 2>/dev/null; then
  echo "✗ 无匹配关键词应退出码 1" >&2
  exit 1
fi

echo "== import：非空库拒绝 + --merge 合并 + 坏行上报 =="
zdata="$data/z-smoke.txt"
printf '/smoke-imported|1|1704067200\nbad line\n' > "$zdata"
if _JB_DATA_DIR="$data" _Z_DATA="$zdata" "$bin" import z 2>/dev/null; then
  echo "✗ 非空库 import 无 --merge 应退出码 1" >&2
  exit 1
fi
out=$(_JB_DATA_DIR="$data" _Z_DATA="$zdata" "$bin" import --merge z 2>&1)
if [ "$out" != "$zdata:2: invalid entry: bad line" ]; then
  echo "✗ import 坏行上报不符: [$out]" >&2
  exit 1
fi
if ! _JB_DATA_DIR="$data" "$bin" query --all --list | grep -q '^/smoke-imported$'; then
  echo "✗ import 后库中应有 /smoke-imported" >&2
  exit 1
fi

echo "✓ smoke 全绿"
