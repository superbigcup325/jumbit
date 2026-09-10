#!/usr/bin/env bash
# 性能规模集：百万行 z 格式数据的 import/query 计时与峰值内存（jumbit vs 上游 zoxide）。
#
# 场景（计时面）：
#   imp    import z                    —— lines 行输入，唯一路径轮转（每路径 3-4 次
#                                        重复触发 dedup 累加）；坏行 ~1% 走 stderr 上报
#   qall   query --list --score --all  —— 全量输出（载入+解码+排序+格式化+写出全链；
#                                        排序标脏，每轮查询都全量落盘一次，两侧一致）
#   qkw    query src --all             —— 关键词命中末组件约 1/10 条目、单结果输出
#                                        （关键词匹配扫描为主）
#   qtsv   query --tsv --all           —— jumbit 扩展数据通道全量输出（上游无对应，仅记录）
#
# 判定：不求快过上游，只求数字健康（同量级）——是否立项优化由数字决定。
#
# 环境注记：import 场景设 MAXAGE=u32::MAX 压住老化。百万行 rank 累计总量远超
# 默认 10000，默认值下老化因子把全部条目缩到 <1 清空库，查询场景将测空库
# （老化语义对拍一致性由 dataset_check.sh 覆盖，此处只需要库存活）。
# u32::MAX 下老化仍会触发（rank 累计 ~5.6e9 > 4.29e9，因子 ~0.69）：rank 和
# 过小的条目被清（约一成，两侧一致削）——真实老化路径本就是测量面的一部分，
# 库条目数因此略低于唯一路径数，属预期。
#
# 依赖：zoxide（PATH）、python3、jumbit release 二进制（moon build --release）。
# 计时包装：scripts/perf_run.py（wall + 子进程峰值 RSS，不依赖 GNU time）。
# 数据由 gen_dataset.py --unique-paths 生成（固定种子可复现），落 /tmp 不入库。
#
# 用法：bash scripts/perf_check.sh [--quick]
#   --quick  10 万行 / 3 万唯一路径 / 1 轮快跑（校验脚本本身，数字不作数）

set -u
cd "$(dirname "$0")/.."

bin=_build/native/release/build/cmd/main/main.exe
lines=1000000 unique=300000 reps=3
if [ "${1:-}" = "--quick" ]; then
  lines=100000 unique=30000 reps=1
fi
maxage=4294967295  # u32::MAX（两侧 maxage 同域：上游解析为 u32）

need() { command -v "$1" >/dev/null || { echo "✗ 缺依赖: $1" >&2; exit 2; }
}
need zoxide
need python3
[ -x "$bin" ] || { echo "✗ 缺 $bin（先 moon build --release）" >&2; exit 2; }

tmp=$(mktemp -d /tmp/jumbit-perf-XXXX)
trap 'rm -rf "$tmp"' EXIT

echo "== 生成数据集（z 格式 $lines 行 / $unique 唯一路径）=="
python3 scripts/gen_dataset.py --format z --lines "$lines" --unique-paths "$unique" \
  --out "$tmp/z.txt"
echo "数据集 $(wc -c < "$tmp/z.txt") 字节"

for r in $(seq 0 $((reps - 1))); do mkdir -p "$tmp/jb-$r" "$tmp/zo-$r"; done

# timed <tag> <cmd...>：环境经 TIMED_ENV 数组传入（--env=KEY=V，{rep} 占位逐轮展开）
timed() {
  local tag="$1"; shift
  python3 scripts/perf_run.py --reps "$reps" ${TIMED_ENV[@]+"${TIMED_ENV[@]}"} \
    --stdout "$tmp/$tag.out" --stderr "$tmp/$tag.err" -- "$@" >"$tmp/$tag.perf"
}

TIMED_ENV=("--env=_JB_DATA_DIR=$tmp/jb-{rep}" "--env=_JB_MAXAGE=$maxage" "--env=_Z_DATA=$tmp/z.txt")
timed imp.jb "$bin" import z
TIMED_ENV=("--env=_ZO_DATA_DIR=$tmp/zo-{rep}" "--env=_ZO_MAXAGE=$maxage" "--env=_Z_DATA=$tmp/z.txt")
timed imp.zo zoxide import z

TIMED_ENV=("--env=_JB_DATA_DIR=$tmp/jb-{rep}")
timed qall.jb "$bin" query --list --score --all
TIMED_ENV=("--env=_ZO_DATA_DIR=$tmp/zo-{rep}")
timed qall.zo zoxide query -l -s -a

TIMED_ENV=("--env=_JB_DATA_DIR=$tmp/jb-{rep}")
timed qkw.jb "$bin" query src --all
TIMED_ENV=("--env=_ZO_DATA_DIR=$tmp/zo-{rep}")
timed qkw.zo zoxide query src -a

TIMED_ENV=("--env=_JB_DATA_DIR=$tmp/jb-{rep}")
timed qtsv.jb "$bin" query --tsv --all

# 汇总：每场景取最优 wall（噪声下界）；RSS 为该场景子进程峰值（ru_maxrss，KB）
row() { # <场景显示名> <tag>
  awk '{ if (NR == 1 || $2 < minw) minw = $2; rss = $3; if ($4 != 0) bad = 1 }
        END { printf "%.3f %8.1f   %s\n", minw, rss / 1024, (bad ? "非0!" : "0") }' \
    "$tmp/$2.perf" | awk -v name="$1" -v tool="${2##*.}" \
    '{ printf "%-10s %-8s %10s %9s MB  %s\n", name, tool, $1, $2, $3 }'
}

best() { awk '{ if (NR == 1 || $2 < m) m = $2 } END { print m }' "$tmp/$1.perf"; }

echo
echo "== 计时（reps=$reps，取最优 wall；RSS=子进程峰值）=="
echo "场景        工具         wall_s   RSS_MB   退出码"
row "import z" imp.jb
row "import z" imp.zo
row "query all" qall.jb
row "query all" qall.zo
row "query kw" qkw.jb
row "query kw" qkw.zo
row "query tsv" qtsv.jb

jb_n=$(wc -l < "$tmp/qall.jb.out")
zo_n=$(wc -l < "$tmp/qall.zo.out")
echo
echo "库条目数（qall 输出行数）: jumbit=$jb_n zoxide=$zo_n（≈ $unique 减老化削边，两侧应一致）"
echo "import stderr 字节: jb=$(wc -c < "$tmp/imp.jb.err") zo=$(wc -c < "$tmp/imp.zo.err")"
echo "DB 文件字节: jb=$(wc -c < "$tmp/jb-0/db.zo") zo=$(wc -c < "$tmp/zo-0/db.zo")"

fail=0
if [ "$jb_n" -lt $((unique * 8 / 10)) ] || [ "$zo_n" -lt $((unique * 8 / 10)) ]; then
  echo "✗ 条目数远低于唯一路径数——老化清库了？查 MAXAGE" >&2
  fail=1
fi
if [ "$jb_n" != "$zo_n" ]; then
  echo "✗ 两侧条目数不一致" >&2
  fail=1
fi
if [ "$(wc -l < "$tmp/qkw.jb.out")" -ne 1 ] || [ "$(wc -l < "$tmp/qkw.zo.out")" -ne 1 ]; then
  echo "✗ 关键词查询应输出单条" >&2
  fail=1
fi

echo
echo "jumbit/zoxide 时间比（最优 wall，<1 即 jumbit 更快）："
for s in imp qall qkw; do
  printf '  %-5s %.2fx\n' "$s" "$(awk "BEGIN{print $(best "$s.jb") / $(best "$s.zo")}")"
done

if [ "$fail" -ne 0 ]; then
  echo "现场保留: $tmp"
  trap - EXIT
  exit 1
fi
