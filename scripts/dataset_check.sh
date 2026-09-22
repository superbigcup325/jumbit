#!/usr/bin/env bash
# 数据集对拍：jumbit vs 上游 zoxide。裁判是上游实现，预期输出零人工。
#
# 场景：z 系四插件（z/fasd/zsh-z/z.lua）、autojump、atuin（伪 atuin 注入）、
#       aging（低 maxage 强制触发）、--merge 合并。
# 每场景三段查询：-a 全量 dump → 非 --all 查询（真实 FS exists 过滤 + 懒删除）→ -a 复查。
# 对拍面：import 退出码 + stderr（坏行消息）、query stdout、query 退出码。
#
# 【明文迁移窗口期判定域】（2026-09-22，jumbit 先行上游 #1288 明文格式）：
# jumbit 持久化 rank 为两位小数（上游 0.10.0 bincode 仍全精度），量化误差
# ≤0.005 经衰减因子放大后 score 显示位在恰半界处可翻转（实测 5/122 条，
# 差 ≤0.1），并列块内次序随之重排。故 query stdout 判定为：
#   - 路径集合一致（排序后按 path 比对，score 列剥离）
#   - 同一路径 score 数值差 ≤ 0.1（容差取 0.1001 吃浮点噪声；量化上界：0.005×衰减 4 = 0.02，显示
#     位翻转 ±0.1，取 0.1 覆盖）
# stderr（坏行消息）与退出码保持字节级。上游合并 #1288 后两侧同为两位
# 小数，判定域恢复全字节级（届时删本段与本文件的容差逻辑）。
#
# 依赖：zoxide（PATH）、python3、jumbit release 二进制（moon build --release）。
# 数据由 scripts/gen_dataset.py 生成（固定种子可复现）；数据本体落 /tmp 不入库。
#
# 用法：bash scripts/dataset_check.sh [--quick]
#   --quick  每格式 500 行快跑（默认 z 20000 / autojump 12000 / atuin 8000）

set -u
cd "$(dirname "$0")/.."

bin=_build/native/release/build/cmd/main/main.exe
seed=20260908
zlines=20000 ajlines=12000 atlines=8000
if [ "${1:-}" = "--quick" ]; then
  zlines=500 ajlines=500 atlines=500
fi

need() { command -v "$1" >/dev/null || { echo "✗ 缺依赖: $1" >&2; exit 2; }
}
need zoxide
need python3
zo_bin=$(command -v zoxide)
[ -x "$bin" ] || { echo "✗ 缺 $bin（先 moon build --release）" >&2; exit 2; }

tmp=$(mktemp -d /tmp/jumbit-ds-XXXX)
trap 'rm -rf "$tmp"' EXIT
pass=0
fail=0
failed=()

# 生成数据集
python3 scripts/gen_dataset.py --format z        --lines "$zlines"  --out "$tmp/z.txt"        --seed "$seed" >/dev/null
python3 scripts/gen_dataset.py --format autojump --lines "$ajlines" --out "$tmp/aj.txt"       --seed "$seed" >/dev/null
python3 scripts/gen_dataset.py --format atuin    --lines "$atlines" --out "$tmp/atuin.txt"    --seed "$seed" >/dev/null
mkdir -p "$tmp/xdg/autojump"
cp "$tmp/aj.txt" "$tmp/xdg/autojump/autojump.txt"

# 伪 atuin：两侧工具都以 `atuin history list --format=... --print0` 拉取，喂同一份记录
mkdir -p "$tmp/fakebin"
printf '#!/bin/sh\ncat %s/atuin.txt\n' "$tmp" > "$tmp/fakebin/atuin"
chmod +x "$tmp/fakebin/atuin"

# run_case <场景名> <插件名> <数据文件> <附加env串> [额外import参数]
# 附加 env 串按空格分词（KEY=V），两侧共用同一组值
run_case() {
  local name="$1" plugin="$2" data="$3" envs="$4" extra="${5:-}"
  local jd="$tmp/jb-$name" zd="$tmp/zo-$name"
  mkdir -p "$jd" "$zd"

  env _JB_DATA_DIR="$jd" $envs "$bin" import $extra "$plugin" \
    >"$tmp/jb-$name.imp" 2>"$tmp/jb-$name.imp.err"
  local jb_code=$?
  env _ZO_DATA_DIR="$zd" $envs zoxide import $extra "$plugin" \
    >"$tmp/zo-$name.imp" 2>"$tmp/zo-$name.imp.err"
  local zo_code=$?

  # 对拍面=stdout 逐字节 + 退出码。query 的 stderr 不比：miss 提示文案是
  # jumbit 的 UX 选择（上游 -l 无命中静默），退出码已一致（范围划定记入台账）
  env _JB_DATA_DIR="$jd" $envs "$bin" query --list --score --all \
    >"$tmp/jb-$name.q1" 2>/dev/null
  jq1=$?
  env _ZO_DATA_DIR="$zd" $envs zoxide query -l -s -a \
    >"$tmp/zo-$name.q1" 2>/dev/null
  zq1=$?
  # 非 --all：exists 过滤 + 陈旧条目懒删除（对数据库的变更也应对拍一致）
  env _JB_DATA_DIR="$jd" $envs "$bin" query --list --score \
    >"$tmp/jb-$name.q2" 2>/dev/null
  jq2=$?
  env _ZO_DATA_DIR="$zd" $envs zoxide query -l -s \
    >"$tmp/zo-$name.q2" 2>/dev/null
  zq2=$?
  env _JB_DATA_DIR="$jd" $envs "$bin" query --list --score --all \
    >"$tmp/jb-$name.q3" 2>/dev/null
  jq3=$?
  env _ZO_DATA_DIR="$zd" $envs zoxide query -l -s -a \
    >"$tmp/zo-$name.q3" 2>/dev/null
  zq3=$?

  local ok=1 why=""
  if [ "$jb_code" != "$zo_code" ]; then
    ok=0 why="$why import退出码($jb_code!=$zo_code)"
  fi
  if ! cmp -s "$tmp/jb-$name.imp.err" "$tmp/zo-$name.imp.err"; then
    ok=0 why="$why import.stderr分歧"
  fi
  local q jcode zcode ties=0
  for q in q1 q2 q3; do
    # 内容判定（明文迁移窗口期）：
    # ① 路径集合一致（剥 score 列，排序后逐字节）——条目多集与次序无关性
    # ② 同路径 score 数值差 ≤ 0.1（量化上界，见文件头判定域说明）
    # ③ NaN 行不参与②（NaN 显示字面量，只可能两侧同为 NaN 或单侧量化消失）
    # 平分块内的次序是排序算法实现细节，不作要求（不变）
    awk '{ $1=""; sub(/^ +/, ""); print }' "$tmp/jb-$name.$q" | sort > "$tmp/jb-$name.$q.p"
    awk '{ $1=""; sub(/^ +/, ""); print }' "$tmp/zo-$name.$q" | sort > "$tmp/zo-$name.$q.p"
    if ! cmp -s "$tmp/jb-$name.$q.p" "$tmp/zo-$name.$q.p"; then
      ok=0 why="$why $q.路径集合分歧"
    fi
    if ! python3 scripts/score_tolerance_check.py "$tmp/jb-$name.$q" "$tmp/zo-$name.$q" 0.1001 >"$tmp/$name.$q.tol" 2>&1; then
      ok=0 why="$why $q.score容差超限($(cat "$tmp/$name.$q.tol" | tail -1))"
    fi
    # 顺序判定：两侧各自按 score 非递增（NaN 行豁免，主数据集无 NaN）
    if ! awk 'NR>1 && $1 !~ /NaN/ && p1 !~ /NaN/ && $1+0 > p1+0 { exit 1 } { p1=$1 }' "$tmp/jb-$name.$q"; then
      ok=0 why="$why $q.jb非降序"
    fi
    if ! awk 'NR>1 && $1 !~ /NaN/ && p1 !~ /NaN/ && $1+0 > p1+0 { exit 1 } { p1=$1 }' "$tmp/zo-$name.$q"; then
      ok=0 why="$why $q.zo非降序"
    fi
    # 平分顺序信息（不计失败）
    if ! cmp -s "$tmp/jb-$name.$q" "$tmp/zo-$name.$q"; then
      n=$(diff "$tmp/jb-$name.$q" "$tmp/zo-$name.$q" | grep -c '^[<>]' || true)
      ties=$((ties + n))
    fi
    case $q in
      q1) jcode=$jq1; zcode=$zq1 ;;
      q2) jcode=$jq2; zcode=$zq2 ;;
      q3) jcode=$jq3; zcode=$zq3 ;;
    esac
    if [ "$jcode" != "$zcode" ]; then
      ok=0 why="$why $q.退出码($jcode!=$zcode)"
    fi
  done
  if [ "$ties" -gt 0 ]; then
    echo "  · $name 平分顺序差异 $ties 行（非语义，不计失败）"
  fi

  if [ "$ok" = 1 ]; then
    echo "✓ $name"
    pass=$((pass + 1))
  else
    echo "✗ $name →$why"
    fail=$((fail + 1))
    failed+=("$name")
    echo "  --- 首处分歧样本（jb vs zo 排序后）---"
    diff "$tmp/jb-$name.q1.s" "$tmp/zo-$name.q1.s" | head -6 | sed 's/^/  /'
    diff "$tmp/jb-$name.imp.err" "$tmp/zo-$name.imp.err" | head -4 | sed 's/^/  /'
  fi
}

echo "== 对拍数据集（seed=$seed, z=$zlines autojump=$ajlines atuin=$atlines）=="

# D1: z 系四插件（同格式，不同数据文件 env）
run_case "D1-z"      z      "$tmp/z.txt" "_Z_DATA=$tmp/z.txt"
run_case "D1-fasd"   fasd   "$tmp/z.txt" "_FASD_DATA=$tmp/z.txt"
run_case "D1-zshz"   zsh-z  "$tmp/z.txt" "ZSHZ_DATA=$tmp/z.txt"
run_case "D1-zlua"   z.lua  "$tmp/z.txt" "_ZL_DATA=$tmp/z.txt"
# D2: autojump（XDG 定位 + sigmoid 归一）
run_case "D2-autojump" autojump "$tmp/aj.txt" "XDG_DATA_HOME=$tmp/xdg"
# D3: atuin（伪 atuin 注入，连续折叠语义）
run_case "D3-atuin"  atuin  "$tmp/atuin.txt" "PATH=$tmp/fakebin:$PATH"
# D5: aging（低 maxage 强制触发老化路径；z 文件复用）
run_case "D5-aging"  z      "$tmp/z.txt" "_Z_DATA=$tmp/z.txt _JB_MAXAGE=50 _ZO_MAXAGE=50"
# D6: merge（二次导入合并；先无 --merge 直灌空库，再 --merge 合并一遍）
run_case "D6-merge"  z      "$tmp/z.txt" "_Z_DATA=$tmp/z.txt" "--merge"

# D9: query --interactive（伪 fzf 探针矩阵，裁判=上游 zoxide 0.10.0）。
# stdout 逐字节 + 退出码对拍；stderr 仅在双侧均应静默的 case 比较
# （上游错误文案带 "zoxide: " 前缀，且 fzf 取消文案不同——jumbit 静默
# exit 1，README「与 zoxide 的差异」注明）。
# 伪 fzf 用隔离 PATH（目录里只有伪 fzf 或为空）——真 fzf 需要 TTY，
# 隔离目录同时天然绕开。
echo "== D9-fzf：query --interactive 交互对拍 =="
mkdir -p "$tmp/fzf-jd" "$tmp/fzf-zd" "$tmp/fzfbin-empty"
printf '/fzfa|1.0|0\n/fzfb|2.0|0\n' > "$tmp/fzf-z.txt"
env _JB_DATA_DIR="$tmp/fzf-jd" _Z_DATA="$tmp/fzf-z.txt" "$bin" import z >/dev/null 2>&1
env _ZO_DATA_DIR="$tmp/fzf-zd" _Z_DATA="$tmp/fzf-z.txt" zoxide import z >/dev/null 2>&1

# fzf_case <场景名> <伪fzf脚本体（空=目录无 fzf）> [附加flag] [silent]
fzf_case() {
  local name="$1" body="$2" extra="${3:-}" silent="${4:-}"
  local bindir="$tmp/fzfbin-$name"
  mkdir -p "$bindir"
  if [ -n "$body" ]; then
    printf '#!/bin/sh\n%s\n' "$body" > "$bindir/fzf"
    chmod +x "$bindir/fzf"
  fi
  env _JB_DATA_DIR="$tmp/fzf-jd" PATH="$bindir" "$bin" \
    query --interactive $extra --all \
    >"$tmp/fzf-jb-$name.out" 2>"$tmp/fzf-jb-$name.err"
  local jc=$?
  # 上游以绝对路径调用：隔离 PATH 只放伪 fzf（真 fzf 需要 TTY，隔离同时绕开）
  env _ZO_DATA_DIR="$tmp/fzf-zd" PATH="$bindir" "$zo_bin" \
    query --interactive $extra \
    >"$tmp/fzf-zo-$name.out" 2>"$tmp/fzf-zo-$name.err"
  local zc=$?
  local ok=1 why=""
  [ "$jc" != "$zc" ] && { ok=0; why="$why 退出码($jc!=$zc)"; }
  cmp -s "$tmp/fzf-jb-$name.out" "$tmp/fzf-zo-$name.out" || { ok=0; why="$why stdout分歧"; }
  if [ "$silent" = "silent" ]; then
    cmp -s "$tmp/fzf-jb-$name.err" "$tmp/fzf-zo-$name.err" || { ok=0; why="$why stderr分歧"; }
  fi
  if [ "$ok" = 1 ]; then
    echo "✓ $name"
    pass=$((pass + 1))
  else
    echo "✗ $name →$why"
    fail=$((fail + 1))
    failed+=("$name")
    echo "  jb(rc=$jc) out=$(cat "$tmp/fzf-jb-$name.out" | head -1) err=$(head -1 "$tmp/fzf-jb-$name.err")"
    echo "  zo(rc=$zc) out=$(cat "$tmp/fzf-zo-$name.out" | head -1) err=$(head -1 "$tmp/fzf-zo-$name.err")"
  fi
}
fzf_case D9-pick       'printf "  40.0\t/picked\n"' ""        silent
fzf_case D9-pick-score 'printf "  40.0\t/picked\n"' "--score" silent
fzf_case D9-nopick     'exit 1'
fzf_case D9-exit2      'exit 2'
fzf_case D9-exit42     'exit 42'
fzf_case D9-exit130    'exit 130' "" silent
fzf_case D9-exit200    'exit 200'
fzf_case D9-exit255    'exit 255'
fzf_case D9-short4     'printf "abc\n"'
fzf_case D9-len7       'printf "1234567"' ""        silent
fzf_case D9-absent     ''

echo "== 结果：$pass 通过 / $fail 失败 =="
if [ "$fail" -gt 0 ]; then
  printf '失败场景: %s\n' "${failed[*]}"
  echo "现场保留: $tmp"
  trap - EXIT
  exit 1
fi
rm -rf "$tmp"
