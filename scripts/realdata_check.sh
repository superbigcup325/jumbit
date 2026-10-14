#!/usr/bin/env bash
# Dataset D10: real-data replay. This machine's real accumulated data (not synthetic) is replayed against both sides, byte for byte.
#
# R1 replay of the real zoxide database: parse ~/.local/share/zoxide/db.zo (bincode: u32 version +
#     u64 entry count + {u64 path length, path, f64 rank LE, u64 la LE}, read per upstream 0.10.0's
#     serialize implementation), restore it as a z-format file, then both sides import z + run three queries.
#     Most real paths do exist (some are deleted), so exists filtering and lazy deletion hit a real filesystem.
#     rank uses python's shortest round-trip repr, and Rust's f64::from_str rounds correctly, so the bits match.
# R2 replay of the real atuin: the real atuin binary (v18, measured; no more fake script) imports from the real shell
#     history, and both sides' import atuin goes through the real atuin subprocess.
#     Positioning note (2026-09-27): atuin records imported from a history file carry no directory field
#     (atuin fills the literal unknown), so both sides here produce unknown entries: what gets verified
#     is parser parity, not the quality of the import semantics; live hook records (with cwd) are the target.
#
# Boundary: this machine's real data volume is the replay size (the value is realism, not volume; scale belongs to D9);
# the user's real db.zo is read-only (a zoxide query re-sorts and writes back, so no command is ever run against the real database);
# real paths land only in /tmp and local comparison output, never in the repo, never shared.
#
# Usage: bash scripts/realdata_check.sh
set -u
cd "$(dirname "$0")/.."

bin=_build/native/release/build/cmd/jumbit/jumbit.exe
real_db="$HOME/.local/share/zoxide/db.zo"
histfile="${HISTFILE:-$HOME/.bash_history}"

need() { command -v "$1" >/dev/null || { echo "✗ missing dependency: $1" >&2; exit 2; }
}
need zoxide
need python3
[ -x "$bin" ] || { echo "✗ $bin is missing (run moon build --release first)" >&2; exit 2; }

tmp=$(mktemp -d /tmp/jumbit-real-XXXX)
pass=0
fail=0
failed=()

echo "== D10 real-data replay =="

# ---------- R1: the real zoxide database -> z-format replay ----------
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
    # shortest round-trip repr: Rust's f64::from_str rounds correctly, restoring the bits
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
    [ "$jb_code" != "$zo_code" ] && { ok=0; why="$why import exit code ($jb_code!=$zo_code)"; }
    cmp -s "$tmp/jb-R1.imp" "$tmp/zo-R1.imp" || { ok=0; why="$why import.stdout differs"; }
    cmp -s "$tmp/jb-R1.imp.err" "$tmp/zo-R1.imp.err" || { ok=0; why="$why import.stderr differs"; }

    # three queries: q1 full -> q2 exists filtering + lazy deletion -> q3 re-check
    env _JB_DATA_DIR="$jd" _Z_DATA="$tmp/real-db.z" "$bin" query --list --score --all >"$tmp/jb-R1.q1" 2>/dev/null
    env _ZO_DATA_DIR="$zd" _Z_DATA="$tmp/real-db.z" zoxide query -l -s -a >"$tmp/zo-R1.q1" 2>/dev/null
    env _JB_DATA_DIR="$jd" _Z_DATA="$tmp/real-db.z" "$bin" query --list --score >"$tmp/jb-R1.q2" 2>/dev/null
    env _ZO_DATA_DIR="$zd" _Z_DATA="$tmp/real-db.z" zoxide query -l -s >"$tmp/zo-R1.q2" 2>/dev/null
    env _JB_DATA_DIR="$jd" _Z_DATA="$tmp/real-db.z" "$bin" query --list --score --all >"$tmp/jb-R1.q3" 2>/dev/null
    env _ZO_DATA_DIR="$zd" _Z_DATA="$tmp/real-db.z" zoxide query -l -s -a >"$tmp/zo-R1.q3" 2>/dev/null
    for q in q1 q2 q3; do
      sort -o "$tmp/jb-R1.$q.s" "$tmp/jb-R1.$q"
      sort -o "$tmp/zo-R1.$q.s" "$tmp/zo-R1.$q"
      cmp -s "$tmp/jb-R1.$q.s" "$tmp/zo-R1.$q.s" || { ok=0; why="$why $q.content differs"; }
      if ! awk 'NR>1 && $1 !~ /NaN/ && p1 !~ /NaN/ && $1+0 > p1+0 { exit 1 } { p1=$1 }' "$tmp/jb-R1.$q"; then
        ok=0; why="$why $q.jb not descending"
      fi
    done

    if [ "$ok" = 1 ]; then
      echo "✓ R1 real zoxide database replayed ($n_entries real entries)"
      pass=$((pass + 1))
    else
      echo "✗ R1 real zoxide database replay ->$why"
      fail=$((fail + 1)); failed+=("R1")
      diff "$tmp/jb-R1.q1.s" "$tmp/zo-R1.q1.s" | head -6 | sed 's/^/  /'
      diff "$tmp/jb-R1.imp.err" "$tmp/zo-R1.imp.err" | head -4 | sed 's/^/  /'

    fi
  else
    echo "· R1 skipped: db.zo version is not 3 ($n_entries); the parser only supports upstream 0.10.0's format"
  fi
else
  echo "· R1 skipped: no real database at $real_db"
fi

# ---------- R2: real atuin subprocess replay (import from real shell history) ----------
if command -v atuin >/dev/null; then
  if [ ! -s "$histfile" ]; then
    echo "· R2 skipped: the shell history $histfile is empty or missing"
  else
    # a fresh atuin data directory (idempotent replay); ATUIN_SESSION is set by the real shell hook
    # and atuin v18's history list requires it (without it atuin errors with zero records)
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
    [ "$jb_code" != "$zo_code" ] && { ok=0; why="$why import exit code ($jb_code!=$zo_code)"; }
    cmp -s "$tmp/jb-R2.imp" "$tmp/zo-R2.imp" || { ok=0; why="$why import.stdout differs"; }
    cmp -s "$tmp/jb-R2.imp.err" "$tmp/zo-R2.imp.err" || { ok=0; why="$why import.stderr differs"; }
    env _JB_DATA_DIR="$jd" "$bin" query --list --score --all >"$tmp/jb-R2.q1" 2>/dev/null
    env _ZO_DATA_DIR="$zd" zoxide query -l -s -a >"$tmp/zo-R2.q1" 2>/dev/null
    sort -o "$tmp/jb-R2.q1.s" "$tmp/jb-R2.q1"
    sort -o "$tmp/zo-R2.q1.s" "$tmp/zo-R2.q1"
    cmp -s "$tmp/jb-R2.q1.s" "$tmp/zo-R2.q1.s" || { ok=0; why="$why q1.content differs"; }

    if [ "$ok" = 1 ]; then
      echo "✓ R2 real atuin replayed ($n_records real command records)"
      pass=$((pass + 1))
    else
      echo "✗ R2 real atuin replay ->$why"
      fail=$((fail + 1)); failed+=("R2")
      diff "$tmp/jb-R2.q1.s" "$tmp/zo-R2.q1.s" | head -6 | sed 's/^/  /'
      diff "$tmp/jb-R2.imp.err" "$tmp/zo-R2.imp.err" | head -4 | sed 's/^/  /'

    fi
  fi
else
  echo "· R2 skipped: atuin is not installed"
fi

# ---------- R3: atuin's error path (stderr passed through verbatim) ----------
# Dropping ATUIN_SESSION makes the real atuin error out: upstream inherits stderr verbatim, and jumbit must forward
# it byte for byte (the blank-line divergence a v18 first run caught was on this path). The comparison surface is the two
# tools, not frozen text, so atuin version drift cannot affect the verdict.
if command -v atuin >/dev/null && [ -n "${XDG_DATA_HOME:-}" ]; then
  jd="$tmp/jb-R3" zd="$tmp/zo-R3"
  mkdir -p "$jd" "$zd"
  env -u ATUIN_SESSION _JB_DATA_DIR="$jd" "$bin" import atuin \
    >"$tmp/jb-R3.imp" 2>"$tmp/jb-R3.imp.err"; jb_code=$?
  env -u ATUIN_SESSION _ZO_DATA_DIR="$zd" zoxide import atuin \
    >"$tmp/zo-R3.imp" 2>"$tmp/zo-R3.imp.err"; zo_code=$?

  ok=1; why=""
  [ "$jb_code" != "$zo_code" ] && { ok=0; why="$why exit code ($jb_code!=$zo_code)"; }
  cmp -s "$tmp/jb-R3.imp" "$tmp/zo-R3.imp" || { ok=0; why="$why stdout differs"; }
  cmp -s "$tmp/jb-R3.imp.err" "$tmp/zo-R3.imp.err" || { ok=0; why="$why stderr differs"; }

  if [ "$ok" = 1 ]; then
    echo "✓ R3 atuin error path (stderr passed through byte for byte)"
    pass=$((pass + 1))
  else
    echo "✗ R3 atuin error path ->$why"
    fail=$((fail + 1)); failed+=("R3")
    diff "$tmp/jb-R3.imp.err" "$tmp/zo-R3.imp.err" | head -4 | sed 's/^/  /'

  fi
fi

echo "== result: $pass passed / $fail failed =="
if [ "$fail" -gt 0 ]; then
  printf 'failed legs: %s\n' "${failed[*]}"
  echo "kept the scratch dir: $tmp"
  exit 1
fi
rm -rf "$tmp"
exit 0
