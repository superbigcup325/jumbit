#!/usr/bin/env bash
# 数据集 D8：jumbit 扩展面（query --json / --fuzzy / matched_by / --limit / --tsv /
# describe / export --agents）的 golden 冻结。上游无对应物、无裁判可用，人工核验后的
# golden 文件即裁判；命令面输出逐字节比对（stdout/stderr/退出码三元组）。
#
# 确定性设计（golden 不随机器/时间漂移）：
# - 数据文件为合成路径（/golden/**，任何机器上都不存在，exists 过滤行为恒定）
# - 时间戳只取两类：la=0（×0.25 档，随时间只增不减）与 la=2^40（未来，u64
#   饱和 → ×4 档，公元 3.6 万年前恒定）；不含 <1h/<1d/<1w 漂移档
# - rank 含一个 nan：总分变 NaN → 老化整体跳过，rank 原样入库（确定性复现）
#
# 用法：bash scripts/golden_check.sh [--update]
#   --update  重新生成 scripts/golden/ 下的 golden 文件（变更须人工 diff 审查）
# 依赖：python3、jumbit release 二进制（moon build --release）

set -u
cd "$(dirname "$0")/.."

# Git Bash/MSYS 会把 POSIX 形态参数（合成路径 /golden/**）自动映射为
# Git 安装根的真实路径（probe 实证 /golden/alpha → C:/Program Files/Git/
# golden/alpha），污染查询参数与库内原样路径的精确匹配；禁用之
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'.

bin=_build/native/release/build/cmd/main/main.exe
golden=scripts/golden
mode=check
if [ "${1:-}" = "--update" ]; then
  mode=update
fi
[ -x "$bin" ] || { echo "✗ 缺 $bin（先 moon build --release）" >&2; exit 2; }

tmp=$(mktemp -d /tmp/jumbit-golden-XXXX)
# Windows（Git Bash）下转混合形态：MSYS 的 /tmp 与 Windows 原生程序的
# 「当前盘根 \tmp」是两个真实位置，python3 写数据集与 jumbit 经 _Z_DATA
# 读取必须落在同处；C:/ 形态 bash 工具同样接受。POSIX 无 cygpath 原样
if command -v cygpath >/dev/null; then
  tmp=$(cygpath -m "$tmp")
fi
pass=0
fail=0
failed=()

# ---------- 数据集 ----------

python3 - "$tmp" <<'PY'
import sys
tmp = sys.argv[1]
# 合成数据集：路径永不存在；la 只取 0（×0.25 恒定）与 2^40（未来 → ×4 恒定）；
# nan rank 使总分 NaN → 老化跳过（import 语义的确定性组成部分）
rows = [
    b"/golden/alpha|3.0|0",
    b"/golden/beta|2.0|1099511627776",
    b"/golden/gamma|1.0|0",
    b"/golden/delta/nested|4.0|0",
    b"/golden/delta/other|1.5|1099511627776",
    b'/golden/esc"quote\\slash|1.0|0',
    b"/golden/tab\tand-uni-\xe4\xb8\xad\xe6\x96\x87|1.0|0",
    b"/golden/nan-entry|nan|0",
    b"/golden/Upper-Case|1.0|0",
    b"/golden/service/web-app|2.0|0",
    b"/golden/database/postgres|2.0|0",
    b"/golden/MyApp/logs|1.0|0",
    b"/golden/ctl\x01byte|1.0|0",
]
open(f"{tmp}/dataset.z", "wb").write(b"\n".join(rows) + b"\n")
PY

# ---------- 执行 ----------

mkdir -p "$tmp/db"
export _JB_DATA_DIR="$tmp/db"

# g <case名> <命令...>：运行一条 jumbit 命令，捕获 out/err/code 三元组
g() {
  local case="$1"
  shift
  "$bin" "$@" >"$tmp/$case.out" 2>"$tmp/$case.err"
  echo $? >"$tmp/$case.code"
  strip_cr "$tmp/$case.out" "$tmp/$case.err" "$tmp/$case.code"
}

# 生成模式直接落 scripts/golden/，检查模式留 tmp 比对
if [ "$mode" = update ]; then
  mkdir -p "$golden"
  g() {
    local case="$1"
    shift
    "$bin" "$@" >"$golden/$case.out" 2>"$golden/$case.err"
    echo $? >"$golden/$case.code"
    strip_cr "$golden/$case.out" "$golden/$case.err" "$golden/$case.code"
  }
fi

# 就地改写（GNU/BSD sed 通用）：BSD sed 的 -i 必带后缀参数（会吞掉 sed 表达式），
# 统一走「stdout 落临时文件 mv 回原位」
sed_inplace() {
  local expr="$1"
  shift
  local f
  for f in "$@"; do
    sed "$expr" "$f" >"$f.jt" && mv "$f.jt" "$f"
  done
}

# CRLF 归一化：Windows 下进程输出重定向经文本模式翻译带 \r（Git Bash 侧
# 重定向同样翻译），逐字节比对/冻结前剥离；POSIX 输出无 \r，Linux 侧零影响
strip_cr() {
  tr -d '\r' <"$1" >"$1.nt" && mv "$1.nt" "$1"
}

# genv <case名> <VAR=val>... -- <命令...>：带环境注入的 g（edit 用例：
# VISUAL 指伪 editor、_JB_DATA_DIR 指独立库）
genv() {
  local case="$1"
  shift
  local envs=()
  while [ "$1" != "--" ]; do
    envs+=("$1")
    shift
  done
  shift
  local outdir="$tmp"
  if [ "$mode" = update ]; then
    outdir="$golden"
  fi
  env "${envs[@]}" "$bin" "$@" >"$outdir/$case.out" 2>"$outdir/$case.err"
  echo $? >"$outdir/$case.code"
  sed_inplace "s|$tmp|@JUMBIT_TMP@|g" "$outdir/$case.out" "$outdir/$case.err"
  strip_cr "$outdir/$case.out" "$outdir/$case.err" "$outdir/$case.code"
}

# gs <case名> <命令...>：status 用例专用——status 输出含数据文件绝对路径
# （位于随机 mktemp 目录），比对前归一化为 @JUMBIT_TMP@，两种模式同规则
gs() {
  local case="$1"
  shift
  local outdir="$tmp"
  if [ "$mode" = update ]; then
    outdir="$golden"
  fi
  "$bin" "$@" >"$outdir/$case.out" 2>"$outdir/$case.err"
  echo $? >"$outdir/$case.code"
  sed_inplace "s|$tmp|@JUMBIT_TMP@|g" "$outdir/$case.out" "$outdir/$case.err"
  strip_cr "$outdir/$case.out" "$outdir/$case.err" "$outdir/$case.code"
}

# --- 空库行为 ---
g json-empty-db query --json --all
g list-empty-db query --list --score
g miss-with-kw query --json --all zzznope
gs status-empty status

# --- 导入（坏行零、静默退出 0；插件数据文件走 _Z_DATA，import 不收路径参数）---
export _Z_DATA="$tmp/dataset.z"
g import-quiet import z

# --- 全量面（--all 不触发 exists，必须先于任何非 --all 用例：exists 过滤
#     伴随 TTL 懒删除，会不可逆地改库）---
g text-all query --list --score --all
g text-single query --score --all beta
g text-fuzzy-case-exact query --list --score --all --fuzzy UPPER
g json-all query --json --all
g json-exact-beta query --json --all beta
g json-fuzzy-exact-wins query --json --all --fuzzy beta
g json-fuzzy-serv query --json --all --fuzzy serv
g json-fuzzy-multi query --json --all --fuzzy web serv
g json-fuzzy-nonlast query --json --all --fuzzy myapp
g json-mutex query --json --interactive

# --- --tsv 数据通道（jumbit 扩展；无表头，path 原样不转义；全 --all 不改库，
#     须在懒删除段之前跑才能见到全量行：tab 路径/nan/转义路径）---
g tsv-all query --tsv --all
g tsv-limit-2 query --tsv --all --limit 2
g tsv-mutex-json query --tsv --json --all
g tsv-mutex-interactive query --tsv --interactive

# --- describe / export --agents ---
g describe-note describe /golden/alpha --note "Alpha 服务"
g describe-show describe /golden/alpha
g describe-note-pipe describe /golden/beta --note "db|primary"
g describe-note-uni describe /golden/service/web-app --note "前端 React"
g agents-table export --agents
g describe-clear describe /golden/alpha --note ""
g agents-after-clear export --agents
g describe-note-newline describe /golden/gamma --note "a
b"
g describe-missing describe /golden/nope

# --- status（jumbit 扩展；13 条 / 2 标注为确定态；--check 下 /golden/** 永
#     不存在 → 存在 0/13 恒定）---
gs status-full status
gs status-json status --json
gs status-check status --check

# --- exists 过滤 + TTL 懒删除（改库，放最后并冻结前后状态）---
g json-exists-filtered query --json beta
g text-exists-empty query --list --score
g json-after-lazy query --json --all

# --- --limit 截断（jumbit 扩展；全 --all 数据路径，不触碰上面懒删除后的库状态）---
g json-limit-2 query --json --all --limit 2
g limit-zero query --json --all --limit 0
g limit-mutex query --limit 2
g limit-invalid-value query --json --all --limit abc
g limit-negative query --json --all --limit -1

# --- status 损坏库（独立库目录，exit 1 + stderr）：
#     status-corrupt = legacy db.zo 二进制路径；status-corrupt-plaintext =
#     明文坏行聚合（行号 + 上游逐字文案 + 8 条折叠之外的常规两行）---
mkdir -p "$tmp/db-corrupt"
printf 'garbage-not-a-db' > "$tmp/db-corrupt/db.zo"
_JB_DATA_DIR="$tmp/db-corrupt" gs status-corrupt status
mkdir -p "$tmp/db-corrupt-txt"
printf '1789054423\t00000001.00\t/golden/ok\nbadline2\n1789054423\tzzz\t/golden/x\n' > "$tmp/db-corrupt-txt/db.txt"
_JB_DATA_DIR="$tmp/db-corrupt-txt" gs status-corrupt-plaintext status

# --- edit（jumbit 扩展；伪 editor + 独立库 edit-db，不触碰主库/status 库）：
#     手编库 2 条（/e-keep 带标注、/e-gone 不存在）→ noop 静默 → rename 改
#     /e-keep（note 跟随）→ 未命中/互斥错误面 → prune 移除 /e-gone 出清单 ---
mkdir -p "$tmp/edit-db"
printf '1789054423\t00000001.00\t/e-keep\n1789054423\t00000002.00\t/e-gone\n' > "$tmp/edit-db/db.txt"
printf '/e-keep\tkept-note\n' > "$tmp/edit-db/notes.tsv"
mkdir -p "$tmp/fake-editor"
printf '#!/bin/sh\nexit 0\n' > "$tmp/fake-editor/noop"
printf '#!/bin/sh\nsed s#/e-keep#/e-renamed# "$1" > "$1.jt" && mv "$1.jt" "$1"\n' > "$tmp/fake-editor/rename"
chmod +x "$tmp/fake-editor/noop" "$tmp/fake-editor/rename"
genv edit-noop VISUAL="$tmp/fake-editor/noop" _JB_DATA_DIR="$tmp/edit-db" -- edit
genv edit-rename VISUAL="$tmp/fake-editor/rename" _JB_DATA_DIR="$tmp/edit-db" -- edit
genv describe-renamed _JB_DATA_DIR="$tmp/edit-db" -- describe /e-renamed
genv edit-missing VISUAL="$tmp/fake-editor/noop" _JB_DATA_DIR="$tmp/edit-db" -- edit --rename /nope /x
genv edit-mutex VISUAL="$tmp/fake-editor/noop" _JB_DATA_DIR="$tmp/edit-db" -- edit --rename /a /b --prune
genv edit-prune VISUAL="$tmp/fake-editor/noop" _JB_DATA_DIR="$tmp/edit-db" -- edit --prune

if [ "$mode" = update ]; then
  echo "== golden 已重生成至 $golden/（请 git diff 人工审查后冻结）=="
  rm -rf "$tmp"
  exit 0
fi

# ---------- 比对 ----------

cmp_case() {
  local case="$1" ext="$2" ok=1
  # golden 侧同样剥 \r：防御 checkout 行尾翻译（.gitattributes 已禁止，
  # 此为本地既有工作区的双保险）
  strip_cr "$golden/$case.$ext"
  if ! cmp -s "$tmp/$case.$ext" "$golden/$case.$ext"; then
    ok=0
  fi
  echo "$ok"
}

for case in json-empty-db list-empty-db miss-with-kw import-quiet \
  text-all text-single text-fuzzy-case-exact json-all json-exact-beta \
  json-fuzzy-exact-wins json-fuzzy-serv json-fuzzy-multi json-fuzzy-nonlast \
  json-mutex describe-note describe-show describe-note-pipe describe-note-uni \
  agents-table describe-clear agents-after-clear describe-note-newline \
  describe-missing json-exists-filtered text-exists-empty json-after-lazy \
  json-limit-2 limit-zero limit-mutex limit-invalid-value limit-negative \
  tsv-all tsv-limit-2 tsv-mutex-json tsv-mutex-interactive \
  status-empty status-full status-json status-check status-corrupt status-corrupt-plaintext \
  edit-noop edit-rename describe-renamed edit-missing edit-mutex edit-prune; do
  local_ok=1
  for ext in out err code; do
    [ "$(cmp_case "$case" "$ext")" = 1 ] || local_ok=0
  done
  if [ "$local_ok" = 1 ]; then
    pass=$((pass + 1))
  else
    echo "✗ $case"
    fail=$((fail + 1))
    failed+=("$case")
    for ext in code err out; do
      echo "  --- $ext ---"
      diff "$golden/$case.$ext" "$tmp/$case.$ext" 2>/dev/null | head -4 | sed 's/^/  /'
      echo "  golden bytes: $(od -An -tx1 -N 32 "$golden/$case.$ext" 2>/dev/null | tr -s ' ')"
      echo "  actual bytes: $(od -An -tx1 -N 32 "$tmp/$case.$ext" 2>/dev/null | tr -s ' ')"
    done
  fi
done

echo "== 结果：$pass 通过 / $fail 失败 =="
if [ "$fail" -gt 0 ]; then
  printf '失败用例: %s\n' "${failed[*]}"
  echo "现场保留: $tmp"
  exit 1
fi
rm -rf "$tmp"
