#!/usr/bin/env bash
# End-to-end smoke: build the real binary and, in a temporary data directory, run add -> query -> error exit codes.
# The second integration line of defence, after regression.sh.
set -euo pipefail
export PATH="$HOME/.moon/bin:$PATH"
cd "$(dirname "$0")/.."

data=$(mktemp -d)
target=$(mktemp -d)
# macOS TMPDIR always ends in a slash (…/T/), so "$TMPDIR/name" would hold a "//" that jumbit's resolve_path
# collapses on insert: the recorded path then differs from the expected string. Strip the slash once and join onto
# this base everywhere below (TMPDIR=/tmp/ reproduces the macOS shape on Linux)
tmpbase="${TMPDIR:-/tmp}"
tmpbase="${tmpbase%/}"
# BSD/macOS mktemp requires its template to end in X and cannot take a suffixed form like test.ps1 (GNU can):
# suffixed temporaries go into a fixed name inside a unique directory, cleaned up by the trap
scratch=$(mktemp -d "$tmpbase/jumbit-sfx-XXXX")
trap 'rm -rf "$data" "$target" "$scratch"' EXIT

echo "== building the release binary =="
moon build --release
bin=_build/native/release/build/cmd/jumbit/jumbit.exe

# MSYS/Git Bash turns POSIX paths in argv into Windows form before handing them to jumbit
# (env vars are not converted), so what jumbit records and prints is Windows form; before asserting, pass the expected
# value through the same conversion (cygpath), which is the identity where there is no cygpath
win_path() {
  if command -v cygpath >/dev/null; then
    cygpath -w "$1"
  else
    printf '%s' "$1"
  fi
}

# file paths handed to an external interpreter (pwsh/nu/elvish and other native Windows programs): the mixed form
# (C:/..., understood by both the Windows API and .NET); an MSYS path would be read as
# \tmp\... on the current drive and the file would not be found
win_file() {
  if command -v cygpath >/dev/null; then
    cygpath -m "$1"
  else
    printf '%s' "$1"
  fi
}

echo "== add the target directory =="
_JB_DATA_DIR="$data" "$bin" add "$target"

echo "== query should echo the target directory exactly =="
out=$(_JB_DATA_DIR="$data" "$bin" query)
if [ "$out" != "$(win_path "$target")" ]; then
  echo "✗ query printed [$out] != [$target]" >&2
  exit 1
fi

echo "== init template syntax check (a sample of the argument matrix) =="
# template name -> executable name mapping (the old version ran command -v on the template name, so the nushell/posix/
# powershell branches never actually ran because no such binary was found)
for shell in bash zsh fish elvish nushell posix powershell tcsh xonsh; do
  binname=$shell
  case "$shell" in
    nushell) binname=nu ;;
    powershell) binname=pwsh ;;
    posix) binname=sh ;;
  esac
  if ! command -v "$binname" >/dev/null; then
    echo "  skipping $shell ($binname is not installed)"
    continue
  fi
  for args in "" "--no-cmd" "--cmd cd" "--hook prompt" "--hook pwd --cmd j"; do
    # derive the public command name from args (--no-cmd asserts the internal __jumbit_z)
    no_cmd=0; cmd=j; prev=""
    for w in $args; do
      if [ "$prev" = "--cmd" ]; then cmd="$w"; fi
      [ "$w" = "--no-cmd" ] && no_cmd=1
      prev="$w"
    done
    if [ "$shell" = "bash" ]; then
      _JB_ECHO=1 _JB_RESOLVE_SYMLINKS=1 "$bin" init bash $args | bash -n || { echo "✗ bash -n failed: $args" >&2; exit 1; }
    elif [ "$shell" = "zsh" ]; then
      _JB_ECHO=1 "$bin" init zsh $args | zsh -n || { echo "✗ zsh -n failed: $args" >&2; exit 1; }
    elif [ "$shell" = "fish" ]; then
      _JB_RESOLVE_SYMLINKS=1 "$bin" init fish $args | fish -n || { echo "✗ fish -n failed: $args" >&2; exit 1; }
    elif [ "$shell" = "powershell" ]; then
      psfile=$scratch/jumbit-ps.ps1
      "$bin" init powershell $args > "$psfile"
      psfile_w=$(win_file "$psfile")
      if ! pwsh -NoProfile -Command "\$null = [scriptblock]::Create((Get-Content -Raw '$psfile_w'))"; then
        echo "✗ powershell failed to parse: $args" >&2
        rm -f "$psfile"
        exit 1
      fi
      rm -f "$psfile"
    elif [ "$shell" = "posix" ]; then
      "$bin" init posix $args | sh -n || { echo "✗ sh -n failed: $args" >&2; exit 1; }
    elif [ "$shell" = "tcsh" ]; then
      # tcsh gets a real script-mode load (fixed 2026-09-26: the old loop let tcsh fall into the else branch and
      # compile it as elvish source, so the check was worthless): after source, assert the command/internal alias exists.
      # A multi-line driver file is required: tcsh parses aliases line by line, and in a single -c line an alias
      # invoked on the same line after source is not expanded. Assert by grepping the full alias list (tcsh's `alias name`
      # query exits 0 even for an undefined alias, so it is unusable)
      tcshfile=$scratch/jumbit-tcsh.csh
      "$bin" init tcsh $args > "$tcshfile"
      alias_target=$cmd
      [ "$no_cmd" = 1 ] && alias_target=__jumbit_z
      printf 'source %s\nalias | grep -q "^%s[ \t]" && echo TCSH-OK\nexit 0\n' \
        "$tcshfile" "$alias_target" > "$tcshfile.drv"
      if ! tcsh -f "$tcshfile.drv" 2>/dev/null | grep -q TCSH-OK; then
        echo "✗ tcsh failed to load: $args" >&2
        rm -f "$tcshfile" "$tcshfile.drv"
        exit 1
      fi
      rm -f "$tcshfile" "$tcshfile.drv"
    elif [ "$shell" = "xonsh" ]; then
      # xonsh gets a real script-mode load: after execx, assert the public alias (--no-cmd asserts the internal function)
      xshfile=$scratch/jumbit-xonsh.xsh
      "$bin" init xonsh $args > "$xshfile"
      printf 'execx(open(r"%s").read())\nimport builtins\n' "$xshfile" > "$xshfile.drv"
      if [ "$no_cmd" = 1 ]; then
        # execx defs do not land in the driver script's globals, so loading without throwing is the gate
        :
      else
        printf 'if builtins.aliases.get("%s") is None:\n    exit(1)\n' "$cmd" >> "$xshfile.drv"
      fi
      printf 'print("XONSH-OK")\n' >> "$xshfile.drv"
      if ! xonsh --no-rc "$xshfile.drv" 2>/dev/null | grep -q XONSH-OK; then
        echo "✗ xonsh failed to load: $args" >&2
        rm -f "$xshfile" "$xshfile.drv"
        exit 1
      fi
      rm -f "$xshfile" "$xshfile.drv"
    elif [ "$shell" = "nushell" ]; then
      nufile=$scratch/jumbit-nu.nu
      "$bin" init nushell $args > "$nufile"
      nufile_w=$(win_file "$nufile")
      if ! nu -n -c "nu-check '$nufile_w'" | grep -q true; then
        echo "✗ nushell syntax error: $args" >&2
        rm -f "$nufile"
        exit 1
      fi
      rm -f "$nufile"
    else
      # elvish's syntax gate is parse-level only: the edit: namespace resolves solely in interactive mode, so
      # "cannot find variable $edit:" from a headless compile is expected and exempted
      elfile=$scratch/jumbit-elvish.elv
      errfile=$(mktemp /tmp/jumbit-elvish-err-XXXX)
      "$bin" init elvish $args > "$elfile"
      elfile_w=$(win_file "$elfile")
      rc=0
      elvish -compileonly "$elfile_w" 2> "$errfile" || rc=$?
      if [ $rc -ne 0 ] && grep -q "Parse error" "$errfile"; then
        echo "✗ elvish syntax error: $args" >&2
        cat "$errfile" >&2
        rm -f "$elfile" "$errfile"
        exit 1
      fi
      rm -f "$elfile" "$errfile"
    fi
  done
done

echo "== init bash: real source check =="
eval "$("$bin" init bash --cmd j)"
type __jumbit_z >/dev/null && type __jumbit_zi >/dev/null && type j >/dev/null || {
  echo "✗ the function is undefined after source" >&2
  exit 1
}

echo "== real invocation shapes: bare name on PATH + relative path + the full hook chain =="
# the hook templates call the binary as a bare \command jumbit (a PATH lookup); the rest of this script
# always uses a full path containing /, so the bare-name branch went untested: the old argv[0] heuristic
# ("strip only when it contains /") made every bare-name call report unknown command with exit 2 and the hook
# fail silently. Here the binary is installed as `jumbit` in a temporary PATH prefix to cover all three argv[0] forms.
rdata=$(mktemp -d "$tmpbase/jumbit-real-XXXX")
rtgt=$(mktemp -d "$tmpbase/jumbit-real-tgt-XXXX")
rfrom=$(mktemp -d "$tmpbase/jumbit-real-src-XXXX")
rbin=$(mktemp -d "$tmpbase/jumbit-real-bin-XXXX")
cp "$bin" "$rbin/jumbit"

PATH="$rbin:$PATH" _JB_DATA_DIR="$rdata" jumbit add -- "$rtgt" ||
  { echo "✗ bare-name add on PATH failed (argv[0] stripping regression)" >&2; exit 1; }
out=$(PATH="$rbin:$PATH" _JB_DATA_DIR="$rdata" jumbit query)
if [ "$out" != "$(win_path "$rtgt")" ]; then
  echo "✗ bare-name query printed [$out] != [$rtgt]" >&2
  exit 1
fi
PATH="$rbin:$PATH" _JB_DATA_DIR="$rdata" jumbit status >/dev/null ||
  { echo "✗ bare-name status on PATH failed" >&2; exit 1; }
( cd "$rbin" && _JB_DATA_DIR="$rdata" ./jumbit add -- "$rtgt" >/dev/null ) ||
  { echo "✗ the relative ./jumbit invocation failed" >&2; exit 1; }

# the full hook chain: each shell really sources init and drives the hook, with the j command doing a bare-name query + cd.
# Non-interactive differences: bash/zsh only fire PROMPT_COMMAND/precmd interactively, so call
# __jumbit_hook by hand; fish's --on-variable PWD event fires in script mode too, but it is still called explicitly once.
# --noprofile --norc / --no-rcs / --no-config skip each shell's user configuration.
hook_posix=$scratch/jumbit-hook.sh
cat > "$hook_posix" <<'EOF'
set -e
# the bash hook has an [[ -o history ]] gate that is off by default non-interactively, so turn it on first (zsh has no such gate)
if [ -n "$BASH_VERSION" ]; then set -o history; fi
eval "$(jumbit init "$JUMBIT_HOOK_SHELL" --cmd j)"
cd "$JUMBIT_HOOK_FROM"
__jumbit_hook
j "$JUMBIT_HOOK_KW"
pwd_cmp=$PWD
if command -v cygpath >/dev/null; then pwd_cmp=$(cygpath -w "$PWD"); fi
if [ "$pwd_cmp" != "$JUMBIT_HOOK_TO" ]; then
  echo "✗ j landed in [$PWD] != [$JUMBIT_HOOK_TO]" >&2
  exit 1
fi
EOF
hook_fish=$scratch/jumbit-hook.fish
cat > "$hook_fish" <<'EOF'
# fish 4+'s --no-config implies private mode, and the template hook skips private sessions by design;
# clear it to imitate an ordinary session with no user configuration
set -e fish_private_mode
jumbit init fish --cmd j | source
or exit 1
cd $JUMBIT_HOOK_FROM
__jumbit_hook
or exit 1
j $JUMBIT_HOOK_KW
or exit 1
if [ "$PWD" != "$JUMBIT_HOOK_TO" ]
    echo "✗ j landed in [$PWD] != [$JUMBIT_HOOK_TO]" >&2
    exit 1
end
EOF
for shell in bash zsh; do
  if ! command -v "$shell" >/dev/null; then
    echo "  skipping the $shell hook chain (not installed)"
    continue
  fi
  if [ "$shell" = bash ]; then rcflags=(--noprofile --norc); else rcflags=(--no-rcs); fi
  PATH="$rbin:$PATH" _JB_DATA_DIR="$rdata" JUMBIT_HOOK_SHELL="$shell" \
    JUMBIT_HOOK_FROM="$(win_path "$rfrom")" JUMBIT_HOOK_TO="$(win_path "$rtgt")" JUMBIT_HOOK_KW=real-tgt \
    "$shell" "${rcflags[@]}" "$hook_posix" ||
    { echo "✗ the $shell hook chain failed" >&2; exit 1; }
  # assert the recording per shell: CI may install only one shell, and another must not mask a missing add
  PATH="$rbin:$PATH" _JB_DATA_DIR="$rdata" jumbit query --all --list | grep -qF -- "$(win_path "$rfrom")" ||
    { echo "✗ the $shell hook's add is not in the database (missing $rfrom)" >&2; exit 1; }
done
if command -v fish >/dev/null; then
  PATH="$rbin:$PATH" _JB_DATA_DIR="$rdata" \
    JUMBIT_HOOK_FROM="$(win_path "$rfrom")" JUMBIT_HOOK_TO="$(win_path "$rtgt")" JUMBIT_HOOK_KW=real-tgt \
    fish --no-config "$hook_fish" ||
    { echo "✗ the fish hook chain failed" >&2; exit 1; }
  PATH="$rbin:$PATH" _JB_DATA_DIR="$rdata" jumbit query --all --list | grep -qF -- "$(win_path "$rfrom")" ||
    { echo "✗ the fish hook's add is not in the database (missing $rfrom)" >&2; exit 1; }
else
  echo "  skipping the fish hook chain (not installed)"
fi
rm -rf "$rdata" "$rtgt" "$rfrom" "$rbin" "$hook_posix" "$hook_fish"

echo "== after remove, query finds nothing =="
_JB_DATA_DIR="$data" "$bin" remove -- "$target"
if _JB_DATA_DIR="$data" "$bin" query 2>/dev/null; then
  echo "✗ after remove, query should find nothing (exit code 1)" >&2
  exit 1
fi
# re-add for the following sections
_JB_DATA_DIR="$data" "$bin" add -- "$target"

echo "== --list --score output shape (6.1f score prefix + space + path) =="
out=$(_JB_DATA_DIR="$data" "$bin" query --list --score)
if [ "$(echo "$out" | wc -l)" -lt 1 ]; then
  echo "✗ --list produced no output" >&2
  exit 1
fi
if ! echo "$out" | grep -qE '^ *[0-9]+\.[0-9] .+'; then
  echo "✗ the --score prefix shape is wrong: $out" >&2
  exit 1
fi

echo "== query --json: a single-line JSON array (the agent channel) =="
jdata=$(mktemp -d "$tmpbase/jumbit-json-XXXX")
printf '/smoke-json|1|1704067200\n' > "$jdata/z.txt"
_JB_DATA_DIR="$jdata" _Z_DATA="$jdata/z.txt" "$bin" import z >/dev/null 2>&1
json_out=$(_JB_DATA_DIR="$jdata" "$bin" query --json --all)
expected='[{"path":"/smoke-json","score":0.25,"last_accessed":1704067200,"matched_by":"exact"}]'
if [ "$json_out" != "$expected" ]; then
  echo "✗ --json output is wrong: [$json_out]" >&2
  exit 1
fi
rm -rf "$jdata"

echo "== query --fuzzy: the fallback when an exact pass finds nothing (matched_by=fuzzy) =="
fdata=$(mktemp -d "$tmpbase/jumbit-fz-XXXX")
printf '/smoke-fz/blog/work|1|0\n' > "$fdata/z.txt"
_JB_DATA_DIR="$fdata" _Z_DATA="$fdata/z.txt" "$bin" import z >/dev/null 2>&1
if _JB_DATA_DIR="$fdata" "$bin" query --json --all blog >/dev/null 2>&1; then
  echo "✗ the exact pass should miss" >&2
  exit 1
fi
fz_out=$(_JB_DATA_DIR="$fdata" "$bin" query --json --all --fuzzy blog)
fz_expected='[{"path":"/smoke-fz/blog/work","score":0.25,"last_accessed":0,"matched_by":"fuzzy"}]'
if [ "$fz_out" != "$fz_expected" ]; then
  echo "✗ --fuzzy output is wrong: [$fz_out]" >&2
  exit 1
fi
rm -rf "$fdata"

echo "== export --agents: the project-map Markdown (with pipe escaping) =="
edata=$(mktemp -d "$tmpbase/jumbit-exp-XXXX")
etgt=$(mktemp -d "$tmpbase/jumbit-exp-tgt-XXXX")
_JB_DATA_DIR="$edata" "$bin" add -- "$etgt" >/dev/null
_JB_DATA_DIR="$edata" "$bin" describe "$etgt" --note "后端服务 | 含API" >/dev/null
_JB_DATA_DIR="$edata" "$bin" export --agents | tr -d '\r' > "$edata/map.md"
printf '%s\n' \
  '<!-- jumbit export --agents: project map, ordered by frecency -->' \
  '| Path | Description |' \
  '|---|---|' \
  "| $(win_path "$etgt") | 后端服务 \| 含API |" | tr -d '\r' > "$edata/expected.md"
if ! diff -u "$edata/expected.md" "$edata/map.md"; then
  echo "✗ export --agents output is wrong" >&2
  exit 1
fi
rm -rf "$edata" "$etgt"

echo "== an unknown command should exit 2 =="
if _JB_DATA_DIR="$data" "$bin" frobnicate 2>/dev/null; then
  echo "✗ an unknown command should exit 2" >&2
  exit 1
fi

echo "== keyword query (anchored on the final component) =="
t2=$(mktemp -d "$tmpbase/foo-demo-XXXX")
trap 'rm -rf "$data" "$target" "$t2"' EXIT
_JB_DATA_DIR="$data" "$bin" add -- "$t2"
out=$(_JB_DATA_DIR="$data" "$bin" query foo)
if [ "$out" != "$(win_path "$t2")" ]; then
  echo "✗ query foo printed [$out] != [$t2]" >&2
  exit 1
fi
if _JB_DATA_DIR="$data" "$bin" query nosuchkeyword 2>/dev/null; then
  echo "✗ a non-matching keyword should exit 1" >&2
  exit 1
fi

echo "== import: refusal on a non-empty database + --merge + bad-row reporting =="
zdata="$data/z-smoke.txt"
printf '/smoke-imported|1|1704067200\nbad line\n' > "$zdata"
if _JB_DATA_DIR="$data" _Z_DATA="$zdata" "$bin" import z 2>/dev/null; then
  echo "✗ import into a non-empty database without --merge should exit 1" >&2
  exit 1
fi
out=$(_JB_DATA_DIR="$data" _Z_DATA="$zdata" "$bin" import --merge z 2>&1)
if [ "$out" != "$(win_file "$zdata"):2: invalid entry: bad line" ]; then
  echo "✗ import bad-row reporting is wrong: [$out]" >&2
  exit 1
fi
if ! _JB_DATA_DIR="$data" "$bin" query --all --list | grep -q '^/smoke-imported$'; then
  echo "✗ after import the database should hold /smoke-imported" >&2
  exit 1
fi

echo "✓ smoke all green"
