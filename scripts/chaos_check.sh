#!/usr/bin/env bash
# Dataset D7: the chaos corpus. No crash on bad input, correct bad-row line numbers, byte-identical behaviour vs upstream.
#
# Two judging surfaces:
# - a self-check surface (independent per tool): import/query exit codes in {0,1} (not killed by a signal, no panic
#   trace); every line number reported on stderr falls in 1..record count (the count formula is checked on both sides, so an error shows up)
# - a comparison surface (judge = upstream zoxide): import exit code + stderr + stdout byte for byte;
#   the three query stages (-a full -> non---all with exists filtering and lazy deletion -> -a re-check) sorted, byte for byte,
#   plus the exit code and jumbit-side non-increasing scores
#
# Scenarios: hand-written boundary files (z fields / UTF-8 case by case / shapes, autojump, atuin streams, binary garbage)
#       plus fixed-seed PRNG mutation/truncation (byte-level damage to 2000 valid z lines).
# Chaos expectations are not enumerated up front; consistency is decided by the comparison surface, and wording locked by unit tests counts as a known source.
#
# Depends on: zoxide (on PATH), python3 and the jumbit release binary (moon build --release).
# The data lands in /tmp, never in the repo; the mutation seed is fixed and reproducible.
#
# [The plaintext-migration window\'s judgement domain] (2026-09-22, spec docs/spec-plaintext-edit.md):
# jumbit\'s plaintext ranks carry two decimals and poisoned entries are rescued (NaN->0.01, empty path skipped), which is a settled
# divergence from the judge zoxide 0.10.0\'s bincode (NaN and empty paths survive, ranks are full precision):
#   - scores differ by <= 0.1001 (a half-boundary flip from quantization, as in dataset_check)
#   - a NaN entry on the zo side: any finite value on the jb side passes (rescue semantics §1.3)
#   - an empty-path entry on the zo side: missing on the jb side passes (the plaintext line format cannot express it)
# stderr, exit codes and line numbers stay byte-level. Revisit once upstream merges #1288.
#
# Usage: bash scripts/chaos_check.sh

set -u
cd "$(dirname "$0")/.."

bin=_build/native/release/build/cmd/jumbit/jumbit.exe
seed=20260909

need() { command -v "$1" >/dev/null || { echo "✗ missing dependency: $1" >&2; exit 2; }
}
need zoxide
need python3
[ -x "$bin" ] || { echo "✗ $bin is missing (run moon build --release first)" >&2; exit 2; }

tmp=$(mktemp -d /tmp/jumbit-chaos-XXXX)
pass=0
fail=0
failed=()

# ---------- chaos file generation (all byte-level python, sidestepping shell escaping traps) ----------

python3 - "$tmp" "$seed" <<'PY'
import random, sys
tmp, seed = sys.argv[1], int(sys.argv[2])
w = lambda name, data: open(f"{tmp}/{name}", "wb").write(data)

# z-utf8: bad UTF-8 case by case + a valid control + an EOF truncation + CR interaction + a BOM (the expected wording is
# locked by unit tests; what matters here is the line numbers and whole-batch consistency)
z_utf8 = (
    b"/a|1.5|100\xff\n"            # bad first byte: 1 byte from 10
    b"/b|\xc3cd|100\n"             # bad second byte of a two-byte sequence: 1 byte from 3
    b"/c|\xe0\x80\x80|100\n"       # bad E0 range: 1 byte
    b"/d|\xed\xa0\x80|100\n"       # ED surrogate range: 1 byte
    b"/e|\xf4\x90\x80\x80|100\n"   # bad F4 range: 1 byte
    b"/f|\xe0\xa0\x41|100\n"       # bad third byte of a three-byte sequence: 2 bytes
    b"/g|\xf0\x9f\x92\x41|100\n"   # bad fourth byte of a four-byte sequence: 3 bytes
    b"/h|\xe4\xb8\xad|1.5|100\n"   # a valid non-ASCII control
    b"/i|1.5|100\xc3\r\n"          # after \r is stripped C3 ends the slice -> incomplete
    b"\xef\xbb\xbf/j|1.5|100\n"    # the BOM belongs to the path (both sides parse it the same way)
    b"/k|1.5|100\xc3"              # EOF truncation -> incomplete
)
w("z-utf8.dat", z_utf8)

# z-field: field-parsing boundaries (u64-domain la, float literals, separator shapes)
z_field = (
    b"/a|1.5|18446744073709551615\n"   # la = u64::MAX (accepted, the x4 bucket)
    b"/b|1.5|18446744073709551616\n"   # la overflows u64 -> a bad row
    b"/c|1.5|+5\n"                     # a leading +
    b"/d|1.5|007\n"                    # a leading zero
    b"/e|1.5| 5\n"                     # leading space in la -> a bad row
    b"/f| 1.5|100\n"                   # leading space in rank -> a bad row
    b"/g|1.5 |100\n"                   # trailing space in rank -> a bad row
    b"/h|1e400|100\n"                  # rank overflows -> inf (which aging turns into NaN)
    b"/i|Infinity|100\n"               # a case variant
    b"/j|-inf|100\n"
    b"/k|nan|100\n"
    b"/l|+1.5|100\n"
    b"/m|.5|100\n"
    b"/n|5.|100\n"
    b"/o|1_000|100\n"                  # an underscore -> a bad row
    b"/p|\xef\xbc\x91.5|100\n"         # a full-width digit -> a bad row
    b"/q|1e|100\n"                     # a dangling exponent -> a bad row
    b"/r|0x10|100\n"                   # hexadecimal -> a bad row
    b"no-pipe\n"
    b"|1.5|100\n"                      # an empty path (legal)
    b"/s|1.5|\n"                       # empty la -> a bad row
    b"a|b|c|d|2.0|300\n"               # the extra pipe belongs to the path
    b"/t|2.0|300|\n"                   # a trailing pipe -> empty la -> a bad row
    b"/u|1.5|100"                      # no trailing newline
)
w("z-field.dat", z_field)

# z-shape: shape boundaries (a huge line / a large line number after many blanks / blanks only / an empty file)
w("z-shape.dat",
  b"/big|" + b"9" * 500000 + b"|100\n"           # a 500k-byte numeric field
  + b"x" * 100000 + b"|1.0|100\n"                # a 100k-byte path
  + b"|" * 2000 + b"|1.0|100\n"                  # 2000 consecutive pipes
  + b"\n" * 50000 + b"/after-empty|1.0|100\n")   # a large line number after 50k blank lines
w("z-newlines.dat", b"\n\n\n\n")
w("z-empty.dat", b"")

# aj-chaos: autojump field boundaries
aj = (
    b"3.7\t/home/aj-ok\n"
    b"no-tab-path\n"
    b"\t/no-rank\n"                # an empty rank -> the "empty string" wording
    b"abc\t/bad-rank\n"
    b"\t\t/double-tab\n"           # an empty rank plus an empty first field
    b"1.0\t\n"                     # an empty path
    b"1e400\t/aj-inf\n"
    b"nan\t/aj-nan\n"
    b"-5\t/aj-negative\n"
    b" 1.5\t/aj-space\n"           # a leading space in rank -> a bad row
    b"1.5\t\xffaj-badutf\n"        # a path with bad UTF-8
    b"1.5\t/aj\x00nul\n"           # a path containing NUL
    b"1.5\t/aj-crlf\r\n"           # CRLF (the file source strips \r -> a clean path)
    b"1.5\t/aj-noeol"              # no trailing newline
)
import os
os.makedirs(f"{tmp}/xdg-chaos/autojump", exist_ok=True)
w("xdg-chaos/autojump/autojump.txt", aj)

# at-chaos: the atuin stream (NUL separated) -- timestamps case by case + folding interaction + bad UTF-8
at = b"\x00".join([
    b"2024-01-01 00:00:00\t/at/one",
    b"2024-01-01 00:00:00\t/at/one",          # consecutive repeats -> folded
    b"2024-01-01 00:00:01\t/at/one",          # the same path repeated non-consecutively -> folded
    b"garbage-no-tab",                        # no \t
    b"\t/at/empty-ts",                        # an empty ts
    b"2023-02-29 00:00:00\t/at/bad-day",      # a leap day in a non-leap year
    b"2024-02-29 00:00:00\t/at/leap",         # a legal leap day
    b"1969-12-31 23:59:59\t/at/pre-epoch",    # pre-epoch (a negative epoch)
    b"0000-01-01 00:00:00\t/at/year-zero",
    b"99999-01-01 00:00:00\t/at/year-overflow",
    b"2024-13-01 00:00:00\t/at/month-range",
    b"2024-01-01 24:00:00\t/at/hour-range",
    b"2024-01-01 00:60:00\t/at/min-range",
    b"2024/01/01 00:00:00\t/at/char-literal",
    b"2024-01-01T00:00:00\t/at/tee-sep",
    b"2024-01-01 00:00:00x\t/at/trailing",
    b"2024-01-01 00:00:00\t/at/bad\xffutf",
    b"2024-01-01 00:00:00\t/at/nu\x00l",      # a NUL inside a record -> it gets split
    b"",                                      # an empty-record placeholder
    b"2024-01-02 00:00:00\t/at/one",          # the same path as the first record (folding interaction across a bad row)
    b"x" * 100000 + b"\t/at/giant",
]) + b"\x00"
w("at-chaos.bin", at)

# z-bin: seeded binary garbage with an ELF header prefix
rng = random.Random(seed)
w("z-bin.dat", b"\x7fELF" + bytes(rng.randrange(256) for _ in range(4092)))
PY

# mutation base: 2000 valid z lines (a real path pool; machine-local consistency is all that is needed)
python3 scripts/gen_dataset.py --format z --lines 2000 --out "$tmp/base.dat" --seed "$seed" >/dev/null

mutate() { # src dst seed rounds: the four operations substitute / delete / insert / cut a span
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

# fake atuin: both sides get the same chaos stream
mkdir -p "$tmp/fakebin"
printf '#!/bin/sh\ncat %s/at-chaos.bin\n' "$tmp" > "$tmp/fakebin/atuin"
chmod +x "$tmp/fakebin/atuin"

# ---------- judging ----------

# record count: the separator count, plus the leftover when there is no trailing separator (same formula as platform split_records)
n_records() { # file nl|nul
python3 - "$1" "$2" <<'PY'
import sys
d = open(sys.argv[1], "rb").read()
sep = b"\x00" if sys.argv[2] == "nul" else b"\n"
print(d.count(sep) + (1 if d and not d.endswith(sep) else 0))
PY
}

# the stderr line-number legality surface: all in 1..N (checked on both jb and zo, so a wrong formula shows up)
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

# run_scenario <name> <plugin> <env string> <data file> <nl|nul>
run_scenario() {
  # $6 may be "no-score-parity": skip the query content tolerance, keep the exit code / descending order / self-check surface.
  # Used for scenarios holding non-finite rank rows (after [#3]\'s import normalization nan no longer poisons the total and
  # inf clamps to the bound, so the two sides\' aging necessarily diverges: upstream 0.10.0 relies on NaN poisoning to skip aging,
  # and jumbit documents that divergence in USAGE\'s differences list; the import three-stream comparison and the self-check surface stay)
  local name="$1" plugin="$2" envs="$3" file="$4" sep="$5" score_parity="${6:-score-parity}"
  local jd="$tmp/jb-$name" zd="$tmp/zo-$name"
  mkdir -p "$jd" "$zd"
  local bin_env="env _JB_DATA_DIR=$jd $envs"
  local zo_env="env _ZO_DATA_DIR=$zd $envs"

  $bin_env "$bin" import "$plugin" >"$tmp/jb-$name.imp" 2>"$tmp/jb-$name.imp.err"
  local jb_code=$?
  $zo_env zoxide import "$plugin" >"$tmp/zo-$name.imp" 2>"$tmp/zo-$name.imp.err"
  local zo_code=$?

  # self-check surface: exit code, panic trace, legal line numbers (checked on both sides)
  local ok=1 why=""
  local c
  for c in "$jb_code" "$zo_code"; do
    case $c in 0 | 1) ;; *) ok=0 why="$why exit code $c" ;; esac
  done
  if has_panic_mark "$tmp/jb-$name.imp.err"; then ok=0 why="$why jb.panic"; fi
  if has_panic_mark "$tmp/zo-$name.imp.err"; then ok=0 why="$why zo.panic"; fi
  local nrec
  nrec=$(n_records "$file" "$sep")
  if ! check_lineno "$tmp/jb-$name.imp.err" "$nrec"; then ok=0 why="$why jb.line number out of range"; fi
  if ! check_lineno "$tmp/zo-$name.imp.err" "$nrec"; then ok=0 why="$why zo.line number out of range"; fi

  # comparison surface: the import three streams, byte for byte
  if [ "$jb_code" != "$zo_code" ]; then ok=0 why="$why import exit code ($jb_code!=$zo_code)"; fi
  cmp -s "$tmp/jb-$name.imp" "$tmp/zo-$name.imp" || { ok=0 why="$why import.stdout differs"; }
  cmp -s "$tmp/jb-$name.imp.err" "$tmp/zo-$name.imp.err" || { ok=0 why="$why import.stderr differs"; }

  # the three query stages: -a full -> exists filtering and lazy deletion -> -a re-check
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
    # window judgement: path sets (empty-path exempt) + score tolerance (one-sided NaN exempt)
    if [ "$score_parity" != "no-score-parity" ]; then
      if ! python3 scripts/score_tolerance_check.py "$tmp/jb-$name.$q" "$tmp/zo-$name.$q" 0.1001 --allow-missing-empty --allow-zo-nan >"$tmp/$name.$q.tol" 2>&1; then
        ok=0 why="$why $q.content differs ($(tail -1 "$tmp/$name.$q.tol"))"
      fi
    fi
    # jumbit-side non-increasing scores (NaN rows exempt)
    if ! awk 'NR>1 && $1 !~ /NaN/ && p1 !~ /NaN/ && $1+0 > p1+0 { exit 1 } { p1=$1 }' "$tmp/jb-$name.$q"; then
      ok=0 why="$why $q.jb not descending"
    fi
    [ "$jcode" != "$zcode" ] && { ok=0 why="$why $q.exit code ($jcode!=$zcode)"; }
  done

  if [ "$ok" = 1 ]; then
    echo "✓ $name"
    pass=$((pass + 1))
  else
    echo "✗ $name →$why"
    fail=$((fail + 1))
    failed+=("$name")
    echo "  --- first import stderr divergence ---"
    diff "$tmp/jb-$name.imp.err" "$tmp/zo-$name.imp.err" | head -6 | sed 's/^/  /'
    echo "  --- first q1 divergence (after sorting) ---"
    diff "$tmp/jb-$name.q1.s" "$tmp/zo-$name.q1.s" | head -6 | sed 's/^/  /'
  fi
}

echo "== D7 chaos corpus (seed=$seed) =="
run_scenario z-utf8    z   "_Z_DATA=$tmp/z-utf8.dat"    "$tmp/z-utf8.dat"    nl
run_scenario z-field   z   "_Z_DATA=$tmp/z-field.dat"   "$tmp/z-field.dat"   nl no-score-parity
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

echo "== result: $pass passed / $fail failed =="
if [ "$fail" -gt 0 ]; then
  printf 'failed scenarios: %s\n' "${failed[*]}"
  echo "kept the scratch dir: $tmp"
  exit 1
fi
rm -rf "$tmp"
