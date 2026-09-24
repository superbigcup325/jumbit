#!/usr/bin/env bash
# 端到端冒烟：构建真实二进制，在临时数据目录跑 add → query → 错误退出码。
# regression.sh 之后的第二道集成防线。
set -euo pipefail
export PATH="$HOME/.moon/bin:$PATH"
cd "$(dirname "$0")/.."

data=$(mktemp -d)
target=$(mktemp -d)
# BSD/macOS mktemp 的模板要求 X 结尾，收不了 test.ps1 等带后缀形态（GNU 允许）：
# 带后缀的临时文件统一落唯一目录内的固定名文件，目录随 trap 清理
scratch=$(mktemp -d "${TMPDIR:-/tmp}/jumbit-sfx-XXXX")
trap 'rm -rf "$data" "$target" "$scratch"' EXIT

echo "== 构建发布二进制 =="
moon build --release
bin=_build/native/release/build/cmd/main/main.exe

# MSYS/Git Bash 会把 argv 里的 POSIX 路径自动转成 Windows 形态传给 jumbit
# （环境变量不做转换），jumbit 记录与回显均为 Windows 形态；断言前把期望值
# 过同一转换（cygpath），POSIX 平台无 cygpath 恒等回原样
win_path() {
  if command -v cygpath >/dev/null; then
    cygpath -w "$1"
  else
    printf '%s' "$1"
  fi
}

# 给外部解释器（pwsh/nu/elvish 等 Windows 原生程序）的文件路径：混合形态
# （C:/...，Windows API 与 .NET 通吃）；MSYS 路径传进去会被当成当前盘
# \tmp\... 而找不到文件
win_file() {
  if command -v cygpath >/dev/null; then
    cygpath -m "$1"
  else
    printf '%s' "$1"
  fi
}

echo "== add 目标目录 =="
_JB_DATA_DIR="$data" "$bin" add "$target"

echo "== query 应精确回显目标目录 =="
out=$(_JB_DATA_DIR="$data" "$bin" query)
if [ "$out" != "$(win_path "$target")" ]; then
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
      psfile=$scratch/jumbit-ps.ps1
      "$bin" init powershell $args > "$psfile"
      psfile_w=$(win_file "$psfile")
      if ! pwsh -NoProfile -Command "\$null = [scriptblock]::Create((Get-Content -Raw '$psfile_w'))"; then
        echo "✗ powershell 解析失败: $args" >&2
        rm -f "$psfile"
        exit 1
      fi
      rm -f "$psfile"
    elif [ "$shell" = "posix" ]; then
      "$bin" init posix $args | sh -n || { echo "✗ sh -n 失败: $args" >&2; exit 1; }
    elif [ "$shell" = "nushell" ]; then
      nufile=$scratch/jumbit-nu.nu
      "$bin" init nushell $args > "$nufile"
      nufile_w=$(win_file "$nufile")
      if ! nu -n -c "nu-check '$nufile_w'" | grep -q true; then
        echo "✗ nushell 语法错误: $args" >&2
        rm -f "$nufile"
        exit 1
      fi
      rm -f "$nufile"
    else
      # elvish 语法门禁 = parse 级：edit: 命名空间仅交互态可解析，
      # headless 编译的 "cannot find variable $edit:" 属预期，豁免
      elfile=$scratch/jumbit-elvish.elv
      errfile=$(mktemp /tmp/jumbit-elvish-err-XXXX)
      "$bin" init elvish $args > "$elfile"
      elfile_w=$(win_file "$elfile")
      rc=0
      elvish -compileonly "$elfile_w" 2> "$errfile" || rc=$?
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
if [ "$out" != "$(win_path "$rtgt")" ]; then
  echo "✗ 裸名 query 输出 [$out] ≠ [$rtgt]" >&2
  exit 1
fi
PATH="$rbin:$PATH" _JB_DATA_DIR="$rdata" jumbit status >/dev/null ||
  { echo "✗ PATH 裸名 status 失败" >&2; exit 1; }
( cd "$rbin" && _JB_DATA_DIR="$rdata" ./jumbit add -- "$rtgt" >/dev/null ) ||
  { echo "✗ 相对路径 ./jumbit 调用失败" >&2; exit 1; }

# hook 全链路：各 shell 真实 source init 并驱动钩子，j 命令走裸名 query + cd。
# 非交互态差异：bash/zsh 的 PROMPT_COMMAND/precmd 仅交互态自动触发，手动调
# __jumbit_hook；fish 的 --on-variable PWD 事件脚本态也触发，仍显式调一次。
# --noprofile --norc / --no-rcs / --no-config 过各自的用户配置。
hook_posix=$scratch/jumbit-hook.sh
cat > "$hook_posix" <<'EOF'
set -e
# bash 钩子有 [[ -o history ]] 门，非交互态默认关——先打开（zsh 钩子无此门）
if [ -n "$BASH_VERSION" ]; then set -o history; fi
eval "$(jumbit init "$JUMBIT_HOOK_SHELL" --cmd j)"
cd "$JUMBIT_HOOK_FROM"
__jumbit_hook
j "$JUMBIT_HOOK_KW"
pwd_cmp=$PWD
if command -v cygpath >/dev/null; then pwd_cmp=$(cygpath -w "$PWD"); fi
if [ "$pwd_cmp" != "$JUMBIT_HOOK_TO" ]; then
  echo "✗ j 落点 [$PWD] ≠ [$JUMBIT_HOOK_TO]" >&2
  exit 1
fi
EOF
hook_fish=$scratch/jumbit-hook.fish
cat > "$hook_fish" <<'EOF'
# fish 4+ 的 --no-config 隐含 private 模式，模板钩子按设计跳过 private 会话；
# 清除以模拟「无用户配置的普通会话」
set -e fish_private_mode
jumbit init fish --cmd j | source
or exit 1
cd $JUMBIT_HOOK_FROM
__jumbit_hook
or exit 1
j $JUMBIT_HOOK_KW
or exit 1
if [ "$PWD" != "$JUMBIT_HOOK_TO" ]
    echo "✗ j 落点 [$PWD] ≠ [$JUMBIT_HOOK_TO]" >&2
    exit 1
end
EOF
for shell in bash zsh; do
  if ! command -v "$shell" >/dev/null; then
    echo "  跳过 $shell hook 链路（未安装）"
    continue
  fi
  if [ "$shell" = bash ]; then rcflags=(--noprofile --norc); else rcflags=(--no-rcs); fi
  PATH="$rbin:$PATH" _JB_DATA_DIR="$rdata" JUMBIT_HOOK_SHELL="$shell" \
    JUMBIT_HOOK_FROM="$(win_path "$rfrom")" JUMBIT_HOOK_TO="$(win_path "$rtgt")" JUMBIT_HOOK_KW=real-tgt \
    "$shell" "${rcflags[@]}" "$hook_posix" ||
    { echo "✗ $shell hook 全链路失败" >&2; exit 1; }
  # 逐 shell 断言入库：CI 可能只装一个 shell，不能让别的 shell 掩盖漏 add
  PATH="$rbin:$PATH" _JB_DATA_DIR="$rdata" jumbit query --all --list | grep -qF -- "$(win_path "$rfrom")" ||
    { echo "✗ $shell hook add 未入库（缺 $rfrom）" >&2; exit 1; }
done
if command -v fish >/dev/null; then
  PATH="$rbin:$PATH" _JB_DATA_DIR="$rdata" \
    JUMBIT_HOOK_FROM="$(win_path "$rfrom")" JUMBIT_HOOK_TO="$(win_path "$rtgt")" JUMBIT_HOOK_KW=real-tgt \
    fish --no-config "$hook_fish" ||
    { echo "✗ fish hook 全链路失败" >&2; exit 1; }
  PATH="$rbin:$PATH" _JB_DATA_DIR="$rdata" jumbit query --all --list | grep -qF -- "$(win_path "$rfrom")" ||
    { echo "✗ fish hook add 未入库（缺 $rfrom）" >&2; exit 1; }
else
  echo "  跳过 fish hook 链路（未安装）"
fi
rm -rf "$rdata" "$rtgt" "$rfrom" "$rbin" "$hook_posix" "$hook_fish"

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
if ! echo "$out" | grep -qE '^ *[0-9]+\.[0-9] .+'; then
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
  "| $(win_path "$etgt") | 后端服务 \| 含API |" > "$edata/expected.md"
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
if [ "$out" != "$(win_path "$t2")" ]; then
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
