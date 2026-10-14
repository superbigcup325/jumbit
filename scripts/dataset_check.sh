#!/usr/bin/env bash
# Dataset comparison: jumbit vs upstream zoxide. The judge is the upstream implementation; nothing here is hand-expected.
#
# Scenarios: the four z-family plugins (z/fasd/zsh-z/z.lua), autojump, atuin (through a fake atuin),
#       aging (forced by a low maxage) and a --merge import.
# Each scenario runs three queries: a full -a dump -> a non---all query (real-FS exists filtering + lazy deletion) -> an -a re-check.
# The comparison surface: import exit code + stderr (bad-row messages), query stdout, query exit code.
#
# [The plaintext-migration window's judgement domain] (2026-09-22, jumbit ahead of upstream #1288):
# jumbit persists rank with two decimals (upstream 0.10.0's bincode is still full precision), so a quantization error
# of up to 0.005, amplified by the decay factor, can flip the score's displayed digit right at a half boundary (measured: 5/122 rows,
# off by up to 0.1), which reorders the tie block. So query stdout is judged as:
#   - the path sets match (compared by path after sorting, with the score column stripped)
#   - the same path's scores differ by <= 0.1 (the tolerance is 0.1001 to absorb float noise; the quantization bound is 0.005 x decay 4 = 0.02, and the
#     displayed digit flips by 0.1, which 0.1 covers)
# stderr (bad-row messages) and exit codes stay byte-level. Once upstream merges #1288 both sides carry two
# decimals and the domain returns to full byte level (at which point this block and the tolerance logic here are deleted).
#
# Depends on: zoxide (on PATH), python3 and the jumbit release binary (moon build --release).
# The data comes from scripts/gen_dataset.py (fixed seed, reproducible) and lands in /tmp, never in the repo.
#
# Usage: bash scripts/dataset_check.sh [--quick]
#   --quick  500 lines per format (defaults: z 20000 / autojump 12000 / atuin 8000)

set -u
cd "$(dirname "$0")/.."

bin=_build/native/release/build/cmd/jumbit/jumbit.exe
seed=20260908
zlines=20000 ajlines=12000 atlines=8000
if [ "${1:-}" = "--quick" ]; then
  zlines=500 ajlines=500 atlines=500
fi

need() { command -v "$1" >/dev/null || { echo "✗ missing dependency: $1" >&2; exit 2; }
}
need zoxide
need python3
zo_bin=$(command -v zoxide)
[ -x "$bin" ] || { echo "✗ $bin is missing (run moon build --release first)" >&2; exit 2; }

tmp=$(mktemp -d /tmp/jumbit-ds-XXXX)
trap 'rm -rf "$tmp"' EXIT
pass=0
fail=0
failed=()

# generate the dataset
python3 scripts/gen_dataset.py --format z        --lines "$zlines"  --out "$tmp/z.txt"        --seed "$seed" >/dev/null
python3 scripts/gen_dataset.py --format autojump --lines "$ajlines" --out "$tmp/aj.txt"       --seed "$seed" >/dev/null
python3 scripts/gen_dataset.py --format atuin    --lines "$atlines" --out "$tmp/atuin.txt"    --seed "$seed" >/dev/null
mkdir -p "$tmp/xdg/autojump"
cp "$tmp/aj.txt" "$tmp/xdg/autojump/autojump.txt"

# fake atuin: both tools pull through `atuin history list --format=... --print0`, so they get the same records
mkdir -p "$tmp/fakebin"
printf '#!/bin/sh\ncat %s/atuin.txt\n' "$tmp" > "$tmp/fakebin/atuin"
chmod +x "$tmp/fakebin/atuin"

# run_case <scenario name> <plugin> <data file> <extra env string> [extra import args]
# the extra env string is split on spaces (KEY=V) and both sides share the same values
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

  # the comparison surface is stdout byte for byte plus the exit code. query's stderr is not compared: the miss wording is
  # a jumbit UX choice (upstream -l is silent on a miss) and the exit codes already agree (the scope is on record)
  env _JB_DATA_DIR="$jd" $envs "$bin" query --list --score --all \
    >"$tmp/jb-$name.q1" 2>/dev/null
  jq1=$?
  env _ZO_DATA_DIR="$zd" $envs zoxide query -l -s -a \
    >"$tmp/zo-$name.q1" 2>/dev/null
  zq1=$?
  # non---all: exists filtering + lazy deletion of stale entries (database changes must match too)
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
    ok=0 why="$why import exit code ($jb_code!=$zo_code)"
  fi
  if ! cmp -s "$tmp/jb-$name.imp.err" "$tmp/zo-$name.imp.err"; then
    ok=0 why="$why import.stderr differs"
  fi
  local q jcode zcode ties=0
  for q in q1 q2 q3; do
    # content judgement (plaintext-migration window):
    # 1. the path sets match (score column stripped, byte for byte after sorting) -- the entry multiset, independent of order
    # 2. the same path's scores differ by <= 0.1 (the quantization bound, see the judgement domain at the top)
    # 3. NaN rows are exempt from 2 (NaN is a display literal, so either both sides are NaN or quantization dropped it on one)
    # the order inside a tie block is a sort-algorithm detail, not required (unchanged)
    awk '{ $1=""; sub(/^ +/, ""); print }' "$tmp/jb-$name.$q" | sort > "$tmp/jb-$name.$q.p"
    awk '{ $1=""; sub(/^ +/, ""); print }' "$tmp/zo-$name.$q" | sort > "$tmp/zo-$name.$q.p"
    if ! cmp -s "$tmp/jb-$name.$q.p" "$tmp/zo-$name.$q.p"; then
      ok=0 why="$why $q.path sets differ"
    fi
    if ! python3 scripts/score_tolerance_check.py "$tmp/jb-$name.$q" "$tmp/zo-$name.$q" 0.1001 >"$tmp/$name.$q.tol" 2>&1; then
      ok=0 why="$why $q.score over tolerance ($(cat "$tmp/$name.$q.tol" | tail -1))"
    fi
    # order check: each side is non-increasing by score (NaN rows exempt; the main dataset has no NaN)
    if ! awk 'NR>1 && $1 !~ /NaN/ && p1 !~ /NaN/ && $1+0 > p1+0 { exit 1 } { p1=$1 }' "$tmp/jb-$name.$q"; then
      ok=0 why="$why $q.jb not descending"
    fi
    if ! awk 'NR>1 && $1 !~ /NaN/ && p1 !~ /NaN/ && $1+0 > p1+0 { exit 1 } { p1=$1 }' "$tmp/zo-$name.$q"; then
      ok=0 why="$why $q.zo not descending"
    fi
    # tie-order information (not a failure)
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
      ok=0 why="$why $q.exit code ($jcode!=$zcode)"
    fi
  done
  if [ "$ties" -gt 0 ]; then
    echo "  · $name tie-order differs on $ties row(s) (not semantic, not a failure)"
  fi

  if [ "$ok" = 1 ]; then
    echo "✓ $name"
    pass=$((pass + 1))
  else
    echo "✗ $name →$why"
    fail=$((fail + 1))
    failed+=("$name")
    echo "  --- first divergence sample (jb vs zo, after sorting) ---"
    diff "$tmp/jb-$name.q1.s" "$tmp/zo-$name.q1.s" | head -6 | sed 's/^/  /'
    diff "$tmp/jb-$name.imp.err" "$tmp/zo-$name.imp.err" | head -4 | sed 's/^/  /'
  fi
}

echo "== comparison dataset (seed=$seed, z=$zlines autojump=$ajlines atuin=$atlines) =="

# D1: the four z-family plugins (same format, different data-file env)
run_case "D1-z"      z      "$tmp/z.txt" "_Z_DATA=$tmp/z.txt"
run_case "D1-fasd"   fasd   "$tmp/z.txt" "_FASD_DATA=$tmp/z.txt"
run_case "D1-zshz"   zsh-z  "$tmp/z.txt" "ZSHZ_DATA=$tmp/z.txt"
run_case "D1-zlua"   z.lua  "$tmp/z.txt" "_ZL_DATA=$tmp/z.txt"
# D2: autojump (XDG lookup + sigmoid normalization)
run_case "D2-autojump" autojump "$tmp/aj.txt" "XDG_DATA_HOME=$tmp/xdg"
# D3: atuin (fake atuin injected, consecutive-folding semantics)
run_case "D3-atuin"  atuin  "$tmp/atuin.txt" "PATH=$tmp/fakebin:$PATH"
# D5: aging (a low maxage forces the aging path; reuses the z file)
run_case "D5-aging"  z      "$tmp/z.txt" "_Z_DATA=$tmp/z.txt _JB_MAXAGE=50 _ZO_MAXAGE=50"
# D6: merge (a second import merges; first pour into an empty database without --merge, then import again with --merge)
run_case "D6-merge"  z      "$tmp/z.txt" "_Z_DATA=$tmp/z.txt" "--merge"

# D9: query --interactive (a fake-fzf probe matrix, judge = upstream zoxide 0.10.0).
# stdout byte for byte plus the exit code; stderr is compared only for cases where both sides should be silent
# (upstream error wording carries a "zoxide: " prefix, and the fzf-cancel wording differs: jumbit is silent with
# exit 1, as the README's differences list notes).
# the fake fzf uses an isolated PATH (the directory holds only the fake fzf, or nothing): real fzf needs a TTY,
# and the isolated directory sidesteps that for free.
echo "== D9-fzf: query --interactive comparison =="
mkdir -p "$tmp/fzf-jd" "$tmp/fzf-zd" "$tmp/fzfbin-empty"
printf '/fzfa|1.0|0\n/fzfb|2.0|0\n' > "$tmp/fzf-z.txt"
env _JB_DATA_DIR="$tmp/fzf-jd" _Z_DATA="$tmp/fzf-z.txt" "$bin" import z >/dev/null 2>&1
env _ZO_DATA_DIR="$tmp/fzf-zd" _Z_DATA="$tmp/fzf-z.txt" zoxide import z >/dev/null 2>&1

# fzf_case <scenario name> <fake fzf body (empty = no fzf in the dir)> [extra flag] [silent]
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
  # upstream calls by absolute path: the isolated PATH holds only the fake fzf (real fzf needs a TTY, sidestepped here)
  env _ZO_DATA_DIR="$tmp/fzf-zd" PATH="$bindir" "$zo_bin" \
    query --interactive $extra \
    >"$tmp/fzf-zo-$name.out" 2>"$tmp/fzf-zo-$name.err"
  local zc=$?
  local ok=1 why=""
  [ "$jc" != "$zc" ] && { ok=0; why="$why exit code ($jc!=$zc)"; }
  cmp -s "$tmp/fzf-jb-$name.out" "$tmp/fzf-zo-$name.out" || { ok=0; why="$why stdout differs"; }
  if [ "$silent" = "silent" ]; then
    cmp -s "$tmp/fzf-jb-$name.err" "$tmp/fzf-zo-$name.err" || { ok=0; why="$why stderr differs"; }
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

echo "== result: $pass passed / $fail failed =="
if [ "$fail" -gt 0 ]; then
  printf 'failed scenarios: %s\n' "${failed[*]}"
  echo "kept the scratch dir: $tmp"
  trap - EXIT
  exit 1
fi
rm -rf "$tmp"
