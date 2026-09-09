#!/usr/bin/env bash
# 数据集 D8：jumbit 扩展面（query --json / --fuzzy / matched_by / --limit / describe /
# export --agents）的 golden 冻结。上游无对应物、无裁判可用，人工核验后的
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

bin=_build/native/release/build/cmd/main/main.exe
golden=scripts/golden
mode=check
if [ "${1:-}" = "--update" ]; then
  mode=update
fi
[ -x "$bin" ] || { echo "✗ 缺 $bin（先 moon build --release）" >&2; exit 2; }

tmp=$(mktemp -d /tmp/jumbit-golden-XXXX)
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
}

# 生成模式直接落 scripts/golden/，检查模式留 tmp 比对
if [ "$mode" = update ]; then
  mkdir -p "$golden"
  g() {
    local case="$1"
    shift
    "$bin" "$@" >"$golden/$case.out" 2>"$golden/$case.err"
    echo $? >"$golden/$case.code"
  }
fi

# --- 空库行为 ---
g json-empty-db query --json --all
g list-empty-db query --list --score
g miss-with-kw query --json --all zzznope

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

if [ "$mode" = update ]; then
  echo "== golden 已重生成至 $golden/（请 git diff 人工审查后冻结）=="
  rm -rf "$tmp"
  exit 0
fi

# ---------- 比对 ----------

cmp_case() {
  local case="$1" ext="$2" ok=1
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
  json-limit-2 limit-zero limit-mutex limit-invalid-value limit-negative; do
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
