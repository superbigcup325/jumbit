#!/usr/bin/env bash
# Dataset D8: golden freeze for jumbit's extension surface (query --json / --fuzzy / matched_by / --limit / --tsv /
# describe / export --agents). Upstream has no counterpart and no judge is available, so the hand-verified
# golden file is the judge; the command surface's output is compared byte for byte (the stdout/stderr/exit-code triple).
#
# Determinism design (the golden does not drift with machine or time):
# - the data holds synthetic paths (/golden/**, which exist nowhere, so the exists filter behaves constantly)
# - timestamps come in two kinds only: la=0 (the x0.25 bucket, which only grows with time) and la=2^40 (the future, where a u64
#   saturates to the x4 bucket, constant until the year 36000); never the drifting <1h/<1d/<1w buckets
# - one rank is nan: the total becomes NaN, so aging is skipped entirely and ranks land as they are (reproducible)
#
# Usage: bash scripts/golden_check.sh [--update]
#   --update  regenerate the golden files under scripts/golden/ (any change needs a hand-reviewed diff)
# Depends on: python3 and the jumbit release binary (moon build --release)

set -u
cd "$(dirname "$0")/.."

# Git Bash/MSYS maps POSIX-shaped arguments (synthetic paths like /golden/**) onto
# real paths under the Git installation (probed: /golden/alpha -> C:/Program Files/Git/
# golden/alpha), which would poison the query arguments' exact match against the raw paths in the database; disable it
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'.

bin=_build/native/release/build/cmd/jumbit/jumbit.exe
golden=scripts/golden
mode=check
if [ "${1:-}" = "--update" ]; then
  mode=update
fi
[ -x "$bin" ] || { echo "✗ $bin is missing (run moon build --release first)" >&2; exit 2; }

tmp=$(mktemp -d /tmp/jumbit-golden-XXXX)
# Under Windows (Git Bash) convert to the mixed form: MSYS's /tmp and a native Windows program's
# "	mp at the current drive root" are two different real places, and the python3 writing the dataset and jumbit reading it through _Z_DATA
# must land in the same one; bash tools accept the C:/ form too. On POSIX, with no cygpath, use it as is
is_win=0
if command -v cygpath >/dev/null; then
  is_win=1
  tmp=$(cygpath -m "$tmp")
fi
pass=0
fail=0
failed=()

# ---------- dataset ----------

python3 - "$tmp" <<'PY'
import sys
tmp = sys.argv[1]
# synthetic dataset: the paths never exist; la is only 0 (a constant x0.25) or 2^40 (the future, a constant x4);
# a nan rank makes the total NaN, so aging is skipped (a deterministic part of the import semantics)
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

# ---------- execution ----------

mkdir -p "$tmp/db"
export _JB_DATA_DIR="$tmp/db"

# g <case name> <command...>: run one jumbit command and capture the out/err/code triple
g() {
  local case="$1"
  shift
  "$bin" "$@" >"$tmp/$case.out" 2>"$tmp/$case.err"
  echo $? >"$tmp/$case.code"
  strip_cr "$tmp/$case.out" "$tmp/$case.err" "$tmp/$case.code"
}

# generate mode writes straight into scripts/golden/, check mode keeps them in tmp for comparison
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

# in-place rewrite (works with both GNU and BSD sed): BSD sed's -i requires a suffix argument (which would swallow the sed expression),
# so everything goes through "stdout to a temp file, then mv back"
sed_inplace() {
  local expr="$1"
  shift
  local f
  for f in "$@"; do
    sed "$expr" "$f" >"$f.jt" && mv "$f.jt" "$f"
  done
}

# CRLF normalization: under Windows, redirected process output goes through text-mode translation and carries \r (Git Bash-side
# redirection translates it too), so it is stripped before the byte comparison/freeze; POSIX output has no \r, so Linux is unaffected
strip_cr() {
  tr -d '\r' <"$1" >"$1.nt" && mv "$1.nt" "$1"
}

# genv <case name> <VAR=val>... -- <command...>: g with environment injection (the edit cases:
# VISUAL points at the fake editor, _JB_DATA_DIR at a separate database)
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

# gs <case name> <command...>: for the status cases -- status output carries the data file's absolute path
# (inside a random mktemp directory), normalized to @JUMBIT_TMP@ before comparison in both modes
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

# --- empty-database behaviour ---
g json-empty-db query --json --all
g list-empty-db query --list --score
g miss-with-kw query --json --all zzznope
gs status-empty status

# --- import (zero bad rows, silent exit 0; the plugin's data file comes from _Z_DATA, import takes no path argument) ---
export _Z_DATA="$tmp/dataset.z"
g import-quiet import z

# --- the full surface (--all does not trigger exists, so it must run before any non---all case: exists filtering
#     comes with TTL lazy deletion, which changes the database irreversibly) ---
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

# --- the --tsv data channel (a jumbit extension; headerless, the path verbatim and unescaped; all --all, so it does not change the database
#     and must run before the lazy-deletion section to see every row: tab path / nan / escaped path) ---
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

# --- status (a jumbit extension; 13 entries / 2 notes is the settled state; under --check /golden/**
#     never exists, so existing 0/13 is constant) ---
gs status-full status
gs status-json status --json
gs status-check status --check

# --- exists filtering + TTL lazy deletion (changes the database; kept last and frozen before and after) ---
g json-exists-filtered query --json beta
g text-exists-empty query --list --score
g json-after-lazy query --json --all

# --- --limit truncation (a jumbit extension; all --all data paths, so it does not touch the post-lazy-deletion state above) ---
g json-limit-2 query --json --all --limit 2
g limit-zero query --json --all --limit 0
g limit-mutex query --limit 2
g limit-invalid-value query --json --all --limit abc
g limit-negative query --json --all --limit -1

# --- status on a corrupt database (a separate database directory, exit 1 + stderr):
#     status-corrupt = the legacy binary db.zo path; status-corrupt-plaintext =
#     the plaintext bad-row aggregate (line number + upstream's verbatim wording + the two normal lines beyond the 8-line fold) ---
mkdir -p "$tmp/db-corrupt"
printf 'garbage-not-a-db' > "$tmp/db-corrupt/db.zo"
_JB_DATA_DIR="$tmp/db-corrupt" gs status-corrupt status
mkdir -p "$tmp/db-corrupt-txt"
printf '1789054423\t00000001.00\t/golden/ok\nbadline2\n1789054423\tzzz\t/golden/x\n' > "$tmp/db-corrupt-txt/db.txt"
_JB_DATA_DIR="$tmp/db-corrupt-txt" gs status-corrupt-plaintext status

# --- edit (a jumbit extension; a fake editor plus a separate edit-db, touching neither the main nor the status database):
#     2 hand-written entries (/e-keep with a note, /e-gone nonexistent) -> noop is silent -> rename changes
#     /e-keep (the note follows) -> the miss/mutex error surface -> prune removes /e-gone from the listing
#     the fake editor needs POSIX sh plus a chmod executable bit, and Windows' CreateProcess
#     cannot run an extensionless script (converting it to a .cmd stub is phase-2 work), so it is skipped under Git Bash ---
if command -v cygpath >/dev/null; then
  echo "  skipping the edit group (the fake editor is a POSIX sh stub; Windows needs a .cmd version)"
else
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
fi

# the top level (--version/-V/no arguments; touches no database, so it goes last)
g version --version
g version-short -V
g version-extra --version x
g noargs

if [ "$mode" = update ]; then
  echo "== golden regenerated into $golden/ (review the git diff, then freeze) =="
  rm -rf "$tmp"
  exit 0
fi

# ---------- comparison ----------

cmp_case() {
  local case="$1" ext="$2" ok=1
  # strip \r on the golden side too: a defence against checkout newline translation (.gitattributes already forbids it,
  # this is a second line of defence for an existing local worktree)
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
  edit-noop edit-rename describe-renamed edit-missing edit-mutex edit-prune \
  version version-short version-extra noargs; do
  # under Windows (Git Bash) the edit group did not run, so the same-named golden is absent and the comparison is skipped
  # (is_win below; mind the left-associativity trap of mixing && and ||, hence the case dispatch)
  if [ "$is_win" = 1 ]; then
    case "$case" in
      edit-noop|edit-rename|describe-renamed|edit-missing|edit-mutex|edit-prune) continue ;;
    esac
  fi
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

echo "== result: $pass passed / $fail failed =="
if [ "$fail" -gt 0 ]; then
  printf 'failed cases: %s\n' "${failed[*]}"
  echo "kept the scratch dir: $tmp"
  exit 1
fi
rm -rf "$tmp"
