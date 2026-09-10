#!/usr/bin/env bash
# 数据集 D10：真实数据回放。本机真实积累数据（非合成）回放对拍，两侧逐字节。
#
# R1 真实 zoxide 库回放：解析 ~/.local/share/zoxide/db.zo（bincode：u32 版本 +
#     u64 条目数 + {u64 路径长, 路径, f64 rank LE, u64 la LE}，按上游 0.10.0
#     serialize 实现读），还原为 z 格式文件 → 两侧 import z + query 三段对拍。
#     真实路径大多真实存在（也有已删除的），exists 过滤与懒删除打真实文件系统。
#     rank 用 python repr 最短往返表示，Rust f64::from_str 正确舍入解析后逐位一致。
# R2 真 atuin 回放：真 atuin 二进制（v18 实测，不再用伪脚本）从真实 shell 历史
#     导入 → 两侧 import atuin 走真 atuin 子进程对拍。
#
# 边界：本机真实数据量即回放规模（价值在真实性不在量，规模面归 D9）；
# 用户真实 db.zo 只读不写（zoxide query 会重排序落盘，故绝不对真实库跑命令）；
# 真实路径只落 /tmp 与本地比对输出，不入库不外传。
#
# 用法：bash scripts/realdata_check.sh
set -u
cd "$(dirname "$0")/.."

bin=_build/native/release/build/cmd/main/main.exe
real_db="$HOME/.local/share/zoxide/db.zo"
histfile="${HISTFILE:-$HOME/.bash_history}"

need() { command -v "$1" >/dev/null || { echo "✗ 缺依赖: $1" >&2; exit 2; }
}
need zoxide
need python3
[ -x "$bin" ] || { echo "✗ 缺 $bin（先 moon build --release）" >&2; exit 2; }

tmp=$(mktemp -d /tmp/jumbit-real-XXXX)
pass=0
fail=0
failed=()

echo "== D10 真实数据回放 =="

# ---------- R1: 真实 zoxide 库 → z 格式回放 ----------
if [ -f "$real_db" ]; then
  n_entries=$(python3 - "$real_db" "$tmp/real-db.z" <<'PY'
import struct, sys
raw = open(sys.argv[1], "rb").read()
off = 0
(version,) = struct.unpack_from("<I", raw, off); off += 4
if version != 3:
    print(f"UNKNOWN_VERSION={version}"); sys.exit(1)
(count,) = struct.unpack_from("<Q", raw, off); off += 8
out = []
for _ in range(count):
    (plen,) = struct.unpack_from("<Q", raw, off); off += 8
    path = raw[off:off + plen].decode("utf-8"); off += plen
    (rank,) = struct.unpack_from("<d", raw, off); off += 8
    (la,) = struct.unpack_from("<Q", raw, off); off += 8
    # repr 最短往返：Rust f64::from_str 正确舍入解析，逐位还原
    out.append(f"{path}|{rank!r}|{la}")
open(sys.argv[2], "w", encoding="utf-8").write("\n".join(out) + "\n")
print(count)
PY
  )
  if [[ "$n_entries" =~ ^[0-9]+$ ]]; then
    jd="$tmp/jb-R1" zd="$tmp/zo-R1"
    mkdir -p "$jd" "$zd"
    env _JB_DATA_DIR="$jd" _Z_DATA="$tmp/real-db.z" "$bin" import z \
      >"$tmp/jb-R1.imp" 2>"$tmp/jb-R1.imp.err"; jb_code=$?
    env _ZO_DATA_DIR="$zd" _Z_DATA="$tmp/real-db.z" zoxide import z \
      >"$tmp/zo-R1.imp" 2>"$tmp/zo-R1.imp.err"; zo_code=$?

    ok=1; why=""
    [ "$jb_code" != "$zo_code" ] && { ok=0; why="$why import退出码($jb_code!=$zo_code)"; }
    cmp -s "$tmp/jb-R1.imp" "$tmp/zo-R1.imp" || { ok=0; why="$why import.stdout分歧"; }
    cmp -s "$tmp/jb-R1.imp.err" "$tmp/zo-R1.imp.err" || { ok=0; why="$why import.stderr分歧"; }

    # 三段查询：q1 全量 → q2 exists 过滤 + 懒删除 → q3 复查
    env _JB_DATA_DIR="$jd" _Z_DATA="$tmp/real-db.z" "$bin" query --list --score --all >"$tmp/jb-R1.q1" 2>/dev/null
    env _ZO_DATA_DIR="$zd" _Z_DATA="$tmp/real-db.z" zoxide query -l -s -a >"$tmp/zo-R1.q1" 2>/dev/null
    env _JB_DATA_DIR="$jd" _Z_DATA="$tmp/real-db.z" "$bin" query --list --score >"$tmp/jb-R1.q2" 2>/dev/null
    env _ZO_DATA_DIR="$zd" _Z_DATA="$tmp/real-db.z" zoxide query -l -s >"$tmp/zo-R1.q2" 2>/dev/null
    env _JB_DATA_DIR="$jd" _Z_DATA="$tmp/real-db.z" "$bin" query --list --score --all >"$tmp/jb-R1.q3" 2>/dev/null
    env _ZO_DATA_DIR="$zd" _Z_DATA="$tmp/real-db.z" zoxide query -l -s -a >"$tmp/zo-R1.q3" 2>/dev/null
    for q in q1 q2 q3; do
      sort -o "$tmp/jb-R1.$q.s" "$tmp/jb-R1.$q"
      sort -o "$tmp/zo-R1.$q.s" "$tmp/zo-R1.$q"
      cmp -s "$tmp/jb-R1.$q.s" "$tmp/zo-R1.$q.s" || { ok=0; why="$why $q.内容分歧"; }
      if ! awk 'NR>1 && $1 !~ /NaN/ && p1 !~ /NaN/ && $1+0 > p1+0 { exit 1 } { p1=$1 }' "$tmp/jb-R1.$q"; then
        ok=0; why="$why $q.jb非降序"
      fi
    done

    if [ "$ok" = 1 ]; then
      echo "✓ R1 真实 zoxide 库回放（$n_entries 条真实条目）"
      pass=$((pass + 1))
    else
      echo "✗ R1 真实 zoxide 库回放 →$why"
      fail=$((fail + 1)); failed+=("R1")
      diff "$tmp/jb-R1.q1.s" "$tmp/zo-R1.q1.s" | head -6 | sed 's/^/  /'
      diff "$tmp/jb-R1.imp.err" "$tmp/zo-R1.imp.err" | head -4 | sed 's/^/  /'

    fi
  else
    echo "· R1 跳过：db.zo 版本非 3（$n_entries），解析器仅支持上游 0.10.0 格式"
  fi
else
  echo "· R1 跳过：未找到真实库 $real_db"
fi

# ---------- R2: 真 atuin 子进程回放（真实 shell 历史导入）----------
if command -v atuin >/dev/null; then
  if [ ! -s "$histfile" ]; then
    echo "· R2 跳过：shell 历史 $histfile 为空/不存在"
  else
    # 全新 atuin 数据目录（幂等重放）；ATUIN_SESSION 为真实 shell 钩子设置的
    # 变量，atuin v18 的 history list 必需（缺失时 atuin 报错零记录）
    export XDG_DATA_HOME="$tmp/xdg" ATUIN_SESSION=jumbit-d10
    mkdir -p "$XDG_DATA_HOME"
    SHELL=/bin/bash HISTFILE="$histfile" atuin import bash >/dev/null 2>"$tmp/atuin-import.err"
    n_records=$(atuin history list --print0 2>/dev/null | tr -dc '\0' | wc -c)

    jd="$tmp/jb-R2" zd="$tmp/zo-R2"
    mkdir -p "$jd" "$zd"
    env _JB_DATA_DIR="$jd" "$bin" import atuin \
      >"$tmp/jb-R2.imp" 2>"$tmp/jb-R2.imp.err"; jb_code=$?
    env _ZO_DATA_DIR="$zd" zoxide import atuin \
      >"$tmp/zo-R2.imp" 2>"$tmp/zo-R2.imp.err"; zo_code=$?

    ok=1; why=""
    [ "$jb_code" != "$zo_code" ] && { ok=0; why="$why import退出码($jb_code!=$zo_code)"; }
    cmp -s "$tmp/jb-R2.imp" "$tmp/zo-R2.imp" || { ok=0; why="$why import.stdout分歧"; }
    cmp -s "$tmp/jb-R2.imp.err" "$tmp/zo-R2.imp.err" || { ok=0; why="$why import.stderr分歧"; }
    env _JB_DATA_DIR="$jd" "$bin" query --list --score --all >"$tmp/jb-R2.q1" 2>/dev/null
    env _ZO_DATA_DIR="$zd" zoxide query -l -s -a >"$tmp/zo-R2.q1" 2>/dev/null
    sort -o "$tmp/jb-R2.q1.s" "$tmp/jb-R2.q1"
    sort -o "$tmp/zo-R2.q1.s" "$tmp/zo-R2.q1"
    cmp -s "$tmp/jb-R2.q1.s" "$tmp/zo-R2.q1.s" || { ok=0; why="$why q1.内容分歧"; }

    if [ "$ok" = 1 ]; then
      echo "✓ R2 真 atuin 回放（$n_records 条真实命令记录）"
      pass=$((pass + 1))
    else
      echo "✗ R2 真 atuin 回放 →$why"
      fail=$((fail + 1)); failed+=("R2")
      diff "$tmp/jb-R2.q1.s" "$tmp/zo-R2.q1.s" | head -6 | sed 's/^/  /'
      diff "$tmp/jb-R2.imp.err" "$tmp/zo-R2.imp.err" | head -4 | sed 's/^/  /'

    fi
  fi
else
  echo "· R2 跳过：未安装 atuin"
fi

# ---------- R3: atuin 报错路径（stderr 透传字节原样）----------
# 去掉 ATUIN_SESSION 使真 atuin 报错：上游继承 stderr 字节原样，jumbit 捕获后
# 转发须逐字节一致（v18 首跑实测抓到的空行分歧即在此路径）。对拍面是两侧
# 工具而非冻结文本，atuin 版本漂移不影响判定。
if command -v atuin >/dev/null && [ -n "${XDG_DATA_HOME:-}" ]; then
  jd="$tmp/jb-R3" zd="$tmp/zo-R3"
  mkdir -p "$jd" "$zd"
  env -u ATUIN_SESSION _JB_DATA_DIR="$jd" "$bin" import atuin \
    >"$tmp/jb-R3.imp" 2>"$tmp/jb-R3.imp.err"; jb_code=$?
  env -u ATUIN_SESSION _ZO_DATA_DIR="$zd" zoxide import atuin \
    >"$tmp/zo-R3.imp" 2>"$tmp/zo-R3.imp.err"; zo_code=$?

  ok=1; why=""
  [ "$jb_code" != "$zo_code" ] && { ok=0; why="$why 退出码($jb_code!=$zo_code)"; }
  cmp -s "$tmp/jb-R3.imp" "$tmp/zo-R3.imp" || { ok=0; why="$why stdout分歧"; }
  cmp -s "$tmp/jb-R3.imp.err" "$tmp/zo-R3.imp.err" || { ok=0; why="$why stderr分歧"; }

  if [ "$ok" = 1 ]; then
    echo "✓ R3 atuin 报错路径（stderr 透传逐字节）"
    pass=$((pass + 1))
  else
    echo "✗ R3 atuin 报错路径 →$why"
    fail=$((fail + 1)); failed+=("R3")
    diff "$tmp/jb-R3.imp.err" "$tmp/zo-R3.imp.err" | head -4 | sed 's/^/  /'

  fi
fi

echo "== 结果：$pass 通过 / $fail 失败 =="
if [ "$fail" -gt 0 ]; then
  printf '失败腿: %s\n' "${failed[*]}"
  echo "现场保留: $tmp"
  exit 1
fi
rm -rf "$tmp"
exit 0
