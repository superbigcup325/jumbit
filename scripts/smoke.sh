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
for shell in bash zsh fish elvish nushell posix powershell tcsh; do
  if ! command -v "$shell" >/dev/null; then
    echo "  跳过 $shell（未安装）"
    continue
  fi
  for args in "" "--no-cmd" "--cmd cd" "--hook prompt" "--hook pwd --cmd j"; do
    if [ "$shell" = "bash" ]; then
      _JB_ECHO=1 _JB_RESOLVE_SYMLINKS=1 "$bin" init bash $args | bash -n || { echo "✗ bash -n 失败: $args" >&2; exit 1; }
    elif [ "$shell" = "zsh" ]; then
      _JB_ECHO=1 "$bin" init zsh $args | zsh -n || { echo "✗ zsh -n 失败: $args" >&2; exit 1; }
    elif [ "$shell" = "fish" ]; then
      _JB_RESOLVE_SYMLINKS=1 "$bin" init fish $args | fish -n || { echo "✗ fish -n 失败: $args" >&2; exit 1; }
    elif [ "$shell" = "powershell" ]; then
      psfile=$(mktemp /tmp/jumbit-ps-XXXX.ps1)
      "$bin" init powershell $args > "$psfile"
      if ! pwsh -NoProfile -Command "\$null = [scriptblock]::Create((Get-Content -Raw '$psfile'))"; then
        echo "✗ powershell 解析失败: $args" >&2
        rm -f "$psfile"
        exit 1
      fi
      rm -f "$psfile"
    elif [ "$shell" = "posix" ]; then
      "$bin" init posix $args | sh -n || { echo "✗ sh -n 失败: $args" >&2; exit 1; }
    elif [ "$shell" = "nushell" ]; then
      nufile=$(mktemp /tmp/jumbit-nu-XXXX.nu)
      "$bin" init nushell $args > "$nufile"
      if ! nu -n -c "nu-check '$nufile'" | grep -q true; then
        echo "✗ nushell 语法错误: $args" >&2
        rm -f "$nufile"
        exit 1
      fi
      rm -f "$nufile"
    else
      # elvish 语法门禁 = parse 级：edit: 命名空间仅交互态可解析，
      # headless 编译的 "cannot find variable $edit:" 属预期，豁免
      elfile=$(mktemp /tmp/jumbit-elvish-XXXX.elv)
      errfile=$(mktemp /tmp/jumbit-elvish-err-XXXX)
      "$bin" init elvish $args > "$elfile"
      rc=0
      elvish -compileonly "$elfile" 2> "$errfile" || rc=$?
      if [ $rc -ne 0 ] && grep -q "Parse error" "$errfile"; then
        echo "✗ elvish 语法错误: $args" >&2
        cat "$errfile" >&2
        rm -f "$elfile" "$errfile"
        exit 1
      fi
      rm -f "$elfile" "$errfile"
    fi
  done
done

echo "== init bash source 实测 =="
eval "$("$bin" init bash --cmd j)"
type __jumbit_z >/dev/null && type __jumbit_zi >/dev/null && type j >/dev/null || {
  echo "✗ source 后函数未定义" >&2
  exit 1
}

echo "== 真实调用形态：PATH 裸名 + 相对路径 + hook 全链路 =="
# hook 模板以 \command jumbit 裸名（PATH 查找）调用二进制；本脚本其余段落
# 全走含 / 的完整路径，探测不到裸名分支——argv[0]「含 / 才剥」的旧启发式
# 曾让裸名调用集体报「未知命令」exit 2 且 hook 静默失败。此处把二进制以
# jumbit 名装入临时 PATH 前缀，按真实形态覆盖三种 argv[0]。
rdata=$(mktemp -d "${TMPDIR:-/tmp}/jumbit-real-XXXX")
rtgt=$(mktemp -d "${TMPDIR:-/tmp}/jumbit-real-tgt-XXXX")
rfrom=$(mktemp -d "${TMPDIR:-/tmp}/jumbit-real-src-XXXX")
rbin=$(mktemp -d "${TMPDIR:-/tmp}/jumbit-real-bin-XXXX")
cp "$bin" "$rbin/jumbit"

PATH="$rbin:$PATH" _JB_DATA_DIR="$rdata" jumbit add -- "$rtgt" ||
  { echo "✗ PATH 裸名 add 失败（argv[0] 剥除回归）" >&2; exit 1; }
out=$(PATH="$rbin:$PATH" _JB_DATA_DIR="$rdata" jumbit query)
if [ "$out" != "$rtgt" ]; then
  echo "✗ 裸名 query 输出 [$out] ≠ [$rtgt]" >&2
  exit 1
fi
PATH="$rbin:$PATH" _JB_DATA_DIR="$rdata" jumbit status >/dev/null ||
  { echo "✗ PATH 裸名 status 失败" >&2; exit 1; }
( cd "$rbin" && _JB_DATA_DIR="$rdata" ./jumbit add -- "$rtgt" >/dev/null ) ||
  { echo "✗ 相对路径 ./jumbit 调用失败" >&2; exit 1; }

# hook 全链路：非交互 bash 不触发 PROMPT_COMMAND，手动调 __jumbit_hook；
# -o history 过 [[ -o history ]] 门；j <关键词> 走裸名 query + cd
hookscript=$(mktemp /tmp/jumbit-hook-XXXX.sh)
cat > "$hookscript" <<'EOF'
set -e -o history
eval "$(jumbit init bash --cmd j)"
cd "$JUMBIT_HOOK_FROM"
__jumbit_hook
j "$JUMBIT_HOOK_KW"
if [ "$PWD" != "$JUMBIT_HOOK_TO" ]; then
  echo "✗ j 落点 [$PWD] ≠ [$JUMBIT_HOOK_TO]" >&2
  exit 1
fi
EOF
PATH="$rbin:$PATH" _JB_DATA_DIR="$rdata" JUMBIT_HOOK_FROM="$rfrom" \
  JUMBIT_HOOK_TO="$rtgt" JUMBIT_HOOK_KW=real-tgt \
  bash --noprofile --norc "$hookscript" ||
  { echo "✗ bash hook 全链路失败" >&2; exit 1; }
PATH="$rbin:$PATH" _JB_DATA_DIR="$rdata" jumbit query --all --list | grep -qF -- "$rfrom" ||
  { echo "✗ hook add 未入库（缺 $rfrom）" >&2; exit 1; }
rm -rf "$rdata" "$rtgt" "$rfrom" "$rbin" "$hookscript"

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

echo "== query --fuzzy：精确零命中兜底（matched_by=fuzzy）=="
fdata=$(mktemp -d "${TMPDIR:-/tmp}/jumbit-fz-XXXX")
printf '/smoke-fz/blog/work|1|0\n' > "$fdata/z.txt"
_JB_DATA_DIR="$fdata" _Z_DATA="$fdata/z.txt" "$bin" import z >/dev/null 2>&1
if _JB_DATA_DIR="$fdata" "$bin" query --json --all blog >/dev/null 2>&1; then
  echo "✗ exact 应 miss" >&2
  exit 1
fi
fz_out=$(_JB_DATA_DIR="$fdata" "$bin" query --json --all --fuzzy blog)
fz_expected='[{"path":"/smoke-fz/blog/work","score":0.25,"last_accessed":0,"matched_by":"fuzzy"}]'
if [ "$fz_out" != "$fz_expected" ]; then
  echo "✗ --fuzzy 输出不符: [$fz_out]" >&2
  exit 1
fi
rm -rf "$fdata"

echo "== export --agents：项目地图 Markdown（含竖线转义）=="
edata=$(mktemp -d "${TMPDIR:-/tmp}/jumbit-exp-XXXX")
etgt=$(mktemp -d "${TMPDIR:-/tmp}/jumbit-exp-tgt-XXXX")
_JB_DATA_DIR="$edata" "$bin" add -- "$etgt" >/dev/null
_JB_DATA_DIR="$edata" "$bin" describe "$etgt" --note "后端服务 | 含API" >/dev/null
_JB_DATA_DIR="$edata" "$bin" export --agents > "$edata/map.md"
printf '%s\n' \
  '<!-- jumbit export --agents：项目地图，按常用度（frecency）降序 -->' \
  '| 路径 | 说明 |' \
  '|---|---|' \
  "| $etgt | 后端服务 \| 含API |" > "$edata/expected.md"
if ! diff -u "$edata/expected.md" "$edata/map.md"; then
  echo "✗ export --agents 输出不符" >&2
  exit 1
fi
rm -rf "$edata" "$etgt"

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
