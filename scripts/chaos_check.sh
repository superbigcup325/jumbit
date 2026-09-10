#!/usr/bin/env bash
# 数据集 D7：混沌语料。坏输入下不崩溃、坏行行号正确、与上游行为逐字节一致。
#
# 双判定面：
# - 自检面（各工具独立）：import/query 退出码 ∈ {0,1}（不被信号杀死/无 panic
#   痕迹）；stderr 上报的行号全部落在 1..记录数（行数公式两侧同验，公式错即暴露）
# - 对拍面（裁判=上游 zoxide）：import 退出码 + stderr + stdout 逐字节；
#   query 三段（-a 全量 → 非 --all 走 exists 过滤与懒删除 → -a 复查）排序后
#   逐字节 + 退出码 + jumbit 侧 score 非递增
#
# 场景：手工边界文件（z 字段/UTF-8 逐类/形状、autojump、atuin 流、二进制垃圾）
#       + 固定种子 PRNG 变异/截断（对 2000 行有效 z 数据做字节级破坏）。
# 混沌期望值不预先枚举，一致性由对拍面裁定；单测锁定的文案类为已知来源。
#
# 依赖：zoxide（PATH）、python3、jumbit release 二进制（moon build --release）。
# 数据本体落 /tmp 不入库；变异种子固定可复现。
#
# 用法：bash scripts/chaos_check.sh

set -u
cd "$(dirname "$0")/.."

bin=_build/native/release/build/cmd/main/main.exe
seed=20260909

need() { command -v "$1" >/dev/null || { echo "✗ 缺依赖: $1" >&2; exit 2; }
}
need zoxide
need python3
[ -x "$bin" ] || { echo "✗ 缺 $bin（先 moon build --release）" >&2; exit 2; }

tmp=$(mktemp -d /tmp/jumbit-chaos-XXXX)
pass=0
fail=0
failed=()

# ---------- 混沌文件生成（全部 python 字节级构造，绕开 shell 转义陷阱） ----------

python3 - "$tmp" "$seed" <<'PY'
import random, sys
tmp, seed = sys.argv[1], int(sys.argv[2])
w = lambda name, data: open(f"{tmp}/{name}", "wb").write(data)

# z-utf8：坏 UTF-8 逐类 + 合法对照 + EOF 截断 + CR 交互 + BOM（期望文案已由
# 单测锁定，此处重在行号与整批一致性）
z_utf8 = (
    b"/a|1.5|100\xff\n"            # 起始坏：1 byte from 10
    b"/b|\xc3cd|100\n"             # 双字节次字节坏：1 byte from 3
    b"/c|\xe0\x80\x80|100\n"       # E0 域坏：1 byte
    b"/d|\xed\xa0\x80|100\n"       # ED 代理区：1 byte
    b"/e|\xf4\x90\x80\x80|100\n"   # F4 域坏：1 byte
    b"/f|\xe0\xa0\x41|100\n"       # 三字节第三字节坏：2 bytes
    b"/g|\xf0\x9f\x92\x41|100\n"   # 四字节第四字节坏：3 bytes
    b"/h|\xe4\xb8\xad|1.5|100\n"   # 合法中文对照
    b"/i|1.5|100\xc3\r\n"          # 剥 \r 后 C3 成切片尾 → incomplete
    b"\xef\xbb\xbf/j|1.5|100\n"    # BOM 属路径（两侧同解析）
    b"/k|1.5|100\xc3"              # EOF 截断 → incomplete
)
w("z-utf8.dat", z_utf8)

# z-field：字段解析边界（u64 域 la、浮点字面量、分隔符形状）
z_field = (
    b"/a|1.5|18446744073709551615\n"   # la = u64::MAX（接受，×4 档）
    b"/b|1.5|18446744073709551616\n"   # la 溢出 u64 → 坏行
    b"/c|1.5|+5\n"                     # 前导 +
    b"/d|1.5|007\n"                    # 前导零
    b"/e|1.5| 5\n"                     # la 前导空格 → 坏行
    b"/f| 1.5|100\n"                   # rank 前导空格 → 坏行
    b"/g|1.5 |100\n"                   # rank 尾随空格 → 坏行
    b"/h|1e400|100\n"                  # rank 溢出 → inf（age 下变 NaN）
    b"/i|Infinity|100\n"               # 大小写变体
    b"/j|-inf|100\n"
    b"/k|nan|100\n"
    b"/l|+1.5|100\n"
    b"/m|.5|100\n"
    b"/n|5.|100\n"
    b"/o|1_000|100\n"                  # 下划线 → 坏行
    b"/p|\xef\xbc\x91.5|100\n"         # 全角数字 → 坏行
    b"/q|1e|100\n"                     # 悬空指数 → 坏行
    b"/r|0x10|100\n"                   # 十六进制 → 坏行
    b"no-pipe\n"
    b"|1.5|100\n"                      # 空路径（合法）
    b"/s|1.5|\n"                       # 空 la → 坏行
    b"a|b|c|d|2.0|300\n"               # 多余管道归路径
    b"/t|2.0|300|\n"                   # 尾管道 → la 为空 → 坏行
    b"/u|1.5|100"                      # 无尾换行
)
w("z-field.dat", z_field)

# z-shape：形状边界（巨行/多空行后大行号/仅空行/空文件）
w("z-shape.dat",
  b"/big|" + b"9" * 500000 + b"|100\n"           # 50 万字节数字段
  + b"x" * 100000 + b"|1.0|100\n"                # 10 万字节路径
  + b"|" * 2000 + b"|1.0|100\n"                  # 2000 连管道
  + b"\n" * 50000 + b"/after-empty|1.0|100\n")   # 5 万空行后大行号
w("z-newlines.dat", b"\n\n\n\n")
w("z-empty.dat", b"")

# aj-chaos：autojump 字段边界
aj = (
    b"3.7\t/home/aj-ok\n"
    b"no-tab-path\n"
    b"\t/no-rank\n"                # 空 rank → empty string 文案
    b"abc\t/bad-rank\n"
    b"\t\t/double-tab\n"           # 空 rank + 空首段
    b"1.0\t\n"                     # 空路径
    b"1e400\t/aj-inf\n"
    b"nan\t/aj-nan\n"
    b"-5\t/aj-negative\n"
    b" 1.5\t/aj-space\n"           # 前导空格 rank → 坏行
    b"1.5\t\xffaj-badutf\n"        # 路径坏 UTF-8
    b"1.5\t/aj\x00nul\n"           # 路径含 NUL
    b"1.5\t/aj-crlf\r\n"           # CRLF（文件源剥 \r → 路径干净）
    b"1.5\t/aj-noeol"              # 无尾换行
)
import os
os.makedirs(f"{tmp}/xdg-chaos/autojump", exist_ok=True)
w("xdg-chaos/autojump/autojump.txt", aj)

# at-chaos：atuin 流（NUL 分隔）——时间戳逐类 + 折叠交互 + 坏 UTF-8
at = b"\x00".join([
    b"2024-01-01 00:00:00\t/at/one",
    b"2024-01-01 00:00:00\t/at/one",          # 连续重复 → 折叠
    b"2024-01-01 00:00:01\t/at/one",          # 同路径非连续重复 → 折叠
    b"garbage-no-tab",                        # 无 \t
    b"\t/at/empty-ts",                        # 空 ts
    b"2023-02-29 00:00:00\t/at/bad-day",      # 非闰年闰日
    b"2024-02-29 00:00:00\t/at/leap",         # 闰日合法
    b"1969-12-31 23:59:59\t/at/pre-epoch",    # 纪元前（负 epoch）
    b"0000-01-01 00:00:00\t/at/year-zero",
    b"99999-01-01 00:00:00\t/at/year-overflow",
    b"2024-13-01 00:00:00\t/at/month-range",
    b"2024-01-01 24:00:00\t/at/hour-range",
    b"2024-01-01 00:60:00\t/at/min-range",
    b"2024/01/01 00:00:00\t/at/char-literal",
    b"2024-01-01T00:00:00\t/at/tee-sep",
    b"2024-01-01 00:00:00x\t/at/trailing",
    b"2024-01-01 00:00:00\t/at/bad\xffutf",
    b"2024-01-01 00:00:00\t/at/nu\x00l",      # 记录内 NUL → 被切分
    b"",                                      # 空记录占位
    b"2024-01-02 00:00:00\t/at/one",          # 与首条同路径（隔坏行折叠交互）
    b"x" * 100000 + b"\t/at/giant",
]) + b"\x00"
w("at-chaos.bin", at)

# z-bin：种子化二进制垃圾 + ELF 头前缀
rng = random.Random(seed)
w("z-bin.dat", b"\x7fELF" + bytes(rng.randrange(256) for _ in range(4092)))
PY

# 变异基座：2000 行有效 z 数据（真实路径池，机器内自洽即可）
python3 scripts/gen_dataset.py --format z --lines 2000 --out "$tmp/base.dat" --seed "$seed" >/dev/null

mutate() { # src dst seed rounds：置换/删/插/截段 四操作
python3 - "$1" "$2" "$3" "$4" <<'PY'
import random, sys
src, dst, seed, rounds = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
data = bytearray(open(src, "rb").read())
rng = random.Random(seed)
for _ in range(rounds):
    if not data:
        break
    op = rng.randrange(4)
    pos = rng.randrange(len(data))
    if op == 0:
        data[pos] = rng.randrange(256)
    elif op == 1:
        del data[pos]
    elif op == 2:
        data.insert(pos, rng.randrange(256))
    else:
        del data[pos:rng.randrange(pos, len(data))]
open(dst, "wb").write(bytes(data))
PY
}
mutate "$tmp/base.dat" "$tmp/z-mut1.dat" "$((seed + 1))" 500
mutate "$tmp/base.dat" "$tmp/z-mut2.dat" "$((seed + 2))" 5000
mutate "$tmp/base.dat" "$tmp/z-mut3.dat" "$((seed + 3))" 50000
for frac in "1:4" "1:2" "3:4"; do
  python3 - "$tmp/base.dat" "$tmp/z-trunc-${frac/:/-}.dat" "$frac" <<'PY'
import sys
d = open(sys.argv[1], "rb").read()
a, b = map(int, sys.argv[3].split(":"))
open(sys.argv[2], "wb").write(d[: len(d) * a // b])
PY
done
python3 - "$tmp/base.dat" "$tmp/z-trunc-eof.dat" <<'PY'
import sys
d = open(sys.argv[1], "rb").read()
open(sys.argv[2], "wb").write(d[: len(d) - 3])
PY

# 伪 atuin：两侧同喂一份混沌流
mkdir -p "$tmp/fakebin"
printf '#!/bin/sh\ncat %s/at-chaos.bin\n' "$tmp" > "$tmp/fakebin/atuin"
chmod +x "$tmp/fakebin/atuin"

# ---------- 判定 ----------

# 记录数：分隔符数 + 无尾分隔符时的残余（与 platform split_records 同式）
n_records() { # file nl|nul
python3 - "$1" "$2" <<'PY'
import sys
d = open(sys.argv[1], "rb").read()
sep = b"\x00" if sys.argv[2] == "nul" else b"\n"
print(d.count(sep) + (1 if d and not d.endswith(sep) else 0))
PY
}

# stderr 行号合法面：全部落在 1..N（jb/zo 同验，公式错即暴露）
check_lineno() { # stderr-file N
  local ok=1 n
  while IFS= read -r line; do
    if [[ "$line" =~ ^line\ ([0-9]+):\  ]]; then
      n="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^.*:([0-9]+):\  ]]; then
      n="${BASH_REMATCH[1]}"
    else
      continue
    fi
    if [ "$n" -lt 1 ] || [ "$n" -gt "$2" ]; then ok=0; fi
  done < "$1"
  [ "$ok" = 1 ]
}

has_panic_mark() { # stderr-file
  grep -qE 'panic|panicked|Aborted|Segmentation|Uncaught|Fatal' "$1"
}

# run_scenario <名> <插件> <env串> <数据文件> <nl|nul>
run_scenario() {
  local name="$1" plugin="$2" envs="$3" file="$4" sep="$5"
  local jd="$tmp/jb-$name" zd="$tmp/zo-$name"
  mkdir -p "$jd" "$zd"
  local bin_env="env _JB_DATA_DIR=$jd $envs"
  local zo_env="env _ZO_DATA_DIR=$zd $envs"

  $bin_env "$bin" import "$plugin" >"$tmp/jb-$name.imp" 2>"$tmp/jb-$name.imp.err"
  local jb_code=$?
  $zo_env zoxide import "$plugin" >"$tmp/zo-$name.imp" 2>"$tmp/zo-$name.imp.err"
  local zo_code=$?

  # 自检面：退出码、panic 痕迹、行号合法（两侧同验）
  local ok=1 why=""
  local c
  for c in "$jb_code" "$zo_code"; do
    case $c in 0 | 1) ;; *) ok=0 why="$why 退出码$c" ;; esac
  done
  if has_panic_mark "$tmp/jb-$name.imp.err"; then ok=0 why="$why jb.panic"; fi
  if has_panic_mark "$tmp/zo-$name.imp.err"; then ok=0 why="$why zo.panic"; fi
  local nrec
  nrec=$(n_records "$file" "$sep")
  if ! check_lineno "$tmp/jb-$name.imp.err" "$nrec"; then ok=0 why="$why jb.行号越界"; fi
  if ! check_lineno "$tmp/zo-$name.imp.err" "$nrec"; then ok=0 why="$why zo.行号越界"; fi

  # 对拍面：import 三流逐字节
  if [ "$jb_code" != "$zo_code" ]; then ok=0 why="$why import退出码($jb_code!=$zo_code)"; fi
  cmp -s "$tmp/jb-$name.imp" "$tmp/zo-$name.imp" || { ok=0 why="$why import.stdout分歧"; }
  cmp -s "$tmp/jb-$name.imp.err" "$tmp/zo-$name.imp.err" || { ok=0 why="$why import.stderr分歧"; }

  # query 三段：-a 全量 → exists 过滤懒删 → -a 复查
  local q jcode zcode
  for q in q1 q2 q3; do
    case $q in
      q1)
        env _JB_DATA_DIR="$jd" $envs "$bin" query --list --score --all >"$tmp/jb-$name.$q" 2>/dev/null
        jcode=$?
        env _ZO_DATA_DIR="$zd" $envs zoxide query -l -s -a >"$tmp/zo-$name.$q" 2>/dev/null
        zcode=$?
        ;;
      q2)
        env _JB_DATA_DIR="$jd" $envs "$bin" query --list --score >"$tmp/jb-$name.$q" 2>/dev/null
        jcode=$?
        env _ZO_DATA_DIR="$zd" $envs zoxide query -l -s >"$tmp/zo-$name.$q" 2>/dev/null
        zcode=$?
        ;;
      q3)
        env _JB_DATA_DIR="$jd" $envs "$bin" query --list --score --all >"$tmp/jb-$name.$q" 2>/dev/null
        jcode=$?
        env _ZO_DATA_DIR="$zd" $envs zoxide query -l -s -a >"$tmp/zo-$name.$q" 2>/dev/null
        zcode=$?
        ;;
    esac
    sort -o "$tmp/jb-$name.$q.s" "$tmp/jb-$name.$q"
    sort -o "$tmp/zo-$name.$q.s" "$tmp/zo-$name.$q"
    cmp -s "$tmp/jb-$name.$q.s" "$tmp/zo-$name.$q.s" || { ok=0 why="$why $q.内容分歧"; }
    # jumbit 侧 score 非递增（NaN 行豁免）
    if ! awk 'NR>1 && $1 !~ /NaN/ && p1 !~ /NaN/ && $1+0 > p1+0 { exit 1 } { p1=$1 }' "$tmp/jb-$name.$q"; then
      ok=0 why="$why $q.jb非降序"
    fi
    [ "$jcode" != "$zcode" ] && { ok=0 why="$why $q.退出码($jcode!=$zcode)"; }
  done

  if [ "$ok" = 1 ]; then
    echo "✓ $name"
    pass=$((pass + 1))
  else
    echo "✗ $name →$why"
    fail=$((fail + 1))
    failed+=("$name")
    echo "  --- import stderr 首处分歧 ---"
    diff "$tmp/jb-$name.imp.err" "$tmp/zo-$name.imp.err" | head -6 | sed 's/^/  /'
    echo "  --- q1 首处分歧（排序后）---"
    diff "$tmp/jb-$name.q1.s" "$tmp/zo-$name.q1.s" | head -6 | sed 's/^/  /'
  fi
}

echo "== D7 混沌语料（seed=$seed）=="
run_scenario z-utf8    z   "_Z_DATA=$tmp/z-utf8.dat"    "$tmp/z-utf8.dat"    nl
run_scenario z-field   z   "_Z_DATA=$tmp/z-field.dat"   "$tmp/z-field.dat"   nl
run_scenario z-shape   z   "_Z_DATA=$tmp/z-shape.dat"   "$tmp/z-shape.dat"   nl
run_scenario z-newlines z  "_Z_DATA=$tmp/z-newlines.dat" "$tmp/z-newlines.dat" nl
run_scenario z-empty   z   "_Z_DATA=$tmp/z-empty.dat"   "$tmp/z-empty.dat"   nl
run_scenario z-bin     z   "_Z_DATA=$tmp/z-bin.dat"     "$tmp/z-bin.dat"     nl
run_scenario aj-chaos  autojump "XDG_DATA_HOME=$tmp/xdg-chaos" "$tmp/xdg-chaos/autojump/autojump.txt" nl
run_scenario at-chaos  atuin "PATH=$tmp/fakebin:$PATH"  "$tmp/at-chaos.bin"  nul
run_scenario z-mut1    z   "_Z_DATA=$tmp/z-mut1.dat"    "$tmp/z-mut1.dat"    nl
run_scenario z-mut2    z   "_Z_DATA=$tmp/z-mut2.dat"    "$tmp/z-mut2.dat"    nl
run_scenario z-mut3    z   "_Z_DATA=$tmp/z-mut3.dat"    "$tmp/z-mut3.dat"    nl
run_scenario z-trunc-1-4 z "_Z_DATA=$tmp/z-trunc-1-4.dat" "$tmp/z-trunc-1-4.dat" nl
run_scenario z-trunc-1-2 z "_Z_DATA=$tmp/z-trunc-1-2.dat" "$tmp/z-trunc-1-2.dat" nl
run_scenario z-trunc-3-4 z "_Z_DATA=$tmp/z-trunc-3-4.dat" "$tmp/z-trunc-3-4.dat" nl
run_scenario z-trunc-eof z "_Z_DATA=$tmp/z-trunc-eof.dat" "$tmp/z-trunc-eof.dat" nl

echo "== 结果：$pass 通过 / $fail 失败 =="
if [ "$fail" -gt 0 ]; then
  printf '失败场景: %s\n' "${failed[*]}"
  echo "现场保留: $tmp"
  exit 1
fi
rm -rf "$tmp"
