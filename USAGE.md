# jumbit user manual

The complete reference: every command and flag, the shell-integration options,
the agent channels, tool integrations, import, how it works, environment
variables, and the differences from zoxide. For failures see
[TROUBLESHOOTING.md](TROUBLESHOOTING.md); for performance numbers see
[BENCHMARKS.md](BENCHMARKS.md).

## Command overview

```bash
jumbit add [--score N] <path>...        record directories (the hook calls this automatically; manual use is fine; --score sets this visit's weight)
jumbit remove <path>...                 remove directories from the database
jumbit query [kw]...                    print the highest-scoring matching directory
  --list                                print every match (descending by score)
  --score                               prefix each line with the score
  --all                                 skip the existence check
  --exclude <path>                      exclude a directory (exact path; glob exclusion goes through _JB_EXCLUDE_DIRS)
  --interactive                         pick interactively with fzf
  --json                                one-line JSON array of every match (agent channel, mutually exclusive with --interactive)
  --fuzzy                               fall back to component substrings when an exact pass finds nothing (jumbit extension)
  --tsv                                 tab-separated path/score/last_accessed/matched_by (jumbit extension, mutually exclusive with --json/--interactive)
  --limit <n>                           print only the first n rows (combines with --list/--json/--tsv, jumbit extension)
jumbit init <shell>                     emit the shell integration (defines j/ji by default, hook=pwd)
  [--cmd C] [--hook pwd|prompt|none] [--no-cmd]
jumbit import <plugin> [--merge]        import history from another tool (plugin ∈ atuin/autojump/fasd/z/z.lua/zsh-z)
jumbit describe <path> [--note text]    view/set a human annotation (--note "" clears it, jumbit extension)
jumbit export --agents                  print the project map as Markdown (jumbit extension)
jumbit status [--json] [--check]        database self-check: entries/notes/format/threshold (--check scans for existence, jumbit extension)
jumbit edit                             edit the database with $VISUAL/$EDITOR (jumbit extension)
  [--rename <old> <new>] | [--prune]    rename a path (the note follows) / drop entries that no longer exist; the three forms are mutually exclusive
jumbit mcp                              start the stdio MCP server (agent channel, jumbit extension, see "For agents")
jumbit help                             show help
jumbit --version                        show the version (-V is a synonym)
```

Syntax and behaviour at a glance:

- The two flag forms are equivalent: `--cmd zj` and `--cmd=zj` (matching upstream's clap). A subcommand's flags and positionals may be interleaved freely (`jumbit init --cmd zj bash` is valid, matching clap's intermix)
- Called with no arguments it prints the usage help to stderr and exits 2 (matching upstream); an explicit `jumbit help` writes to stdout and exits 0
- Repeating a value-taking flag (`--score` / `--exclude` / `--limit` / `--note`) lets the last one win; nothing after `--` is parsed as a flag
- `query` with no keywords prints the highest-scoring entry; `query --list` is silent on empty output with exit code 0 (matching upstream)
- `describe <path>` without `--note` is view mode: it prints the existing annotation and exits 1 when there is none
- The single-result path writes a bare path to stdout, so `cd "$(jumbit query kw)"` works directly
- `query` filters on existence by default and lazily deletes stale entries; use `--all` to bypass that

## Shell integration

```bash
# bash: add to ~/.bashrc
eval "$(jumbit init bash)"
# zsh: ~/.zshrc; fish: use `jumbit init fish | source` in ~/.config/fish/config.fish
# elvish / nushell / posix / powershell / tcsh / xonsh are supported too, the same way

j backend        # jump (with completion)
ji               # interactive jump with fzf (requires fzf)
```

`init` options:

| Option | Effect | Default |
|---|---|---|
| `--cmd C` | Custom command name (both forms: `--cmd cd` / `--cmd=cd`) | `j` (the interactive command `ji` is derived alongside) |
| `--hook pwd\|prompt\|none` | How recording is triggered: on directory change / at prompt time / never automatically | `pwd` |
| `--no-cmd` | Emit only the internal functions, define no public command (alias it yourself) | off |

The full behaviour of `j`:

| Invocation | Behaviour |
|---|---|
| `j` (no arguments) | go home |
| `j -` | go to the previous directory (OLDPWD) |
| `j <existing path>` | go straight to that directory (before keyword matching) |
| `j <keyword>...` | cd to the best frecency match; the destination is recorded afterwards (with `--hook none` nothing is recorded) |
| `ji [keyword]...` | pick interactively with fzf, then cd |

> Test coverage: the full hook chain for bash / zsh / fish runs for real in CI
> (source the init output, drive the hooks, assert the landing point and the
> recording); tcsh / xonsh get a script-mode load gate in smoke (assert the alias
> exists after source/execx); elvish / nushell / posix / powershell keep syntax
> gates (nu-check / sh -n / pwsh parse / elvish compile). All nine templates were
> verified headless on real machines, shell by shell, on 2026-09-27 (script mode
> for bash/zsh/posix/tcsh, script mode for fish/nu/pwsh/xonsh, and elvish in an
> interactive pty). Please open an issue if you find a problem.

## For agents

jumbit's directory memory does not only feed the shell — it feeds coding agents
too. Four channels:

**Machine-readable queries**: `query --json` / `--tsv` are for agent scripts, and
`--limit N` caps the row count to control context cost:

```bash
jumbit query --json backend
```

```json
[{"path":"/home/you/projects/backend-api","score":8,"last_accessed":1789054423,"matched_by":"exact"}]
```

- The key order is fixed — `path, score, last_accessed, matched_by` — one line, byte-stable
- `last_accessed` is epoch seconds; `score` uses the shortest float form (NaN/±Infinity become `null`, the JSON numeric domain)
- `matched_by` is the evidence field: `exact` (a keyword match) or `fuzzy` (a `--fuzzy` substring fallback), so an agent can decide how much to trust the row
- `--tsv` emits headerless tab-separated rows with the same column order as the JSON keys, which suits table-shaped tools:

```
/home/you/projects/backend-api	8	1789054423	exact
```

**Project map**: `describe` attaches a human annotation to a frequent directory
(persisted in the database), and `export --agents` renders them as a Markdown
table to append to AGENTS.md, so an agent opening the workspace immediately knows
what lives where:

```bash
jumbit describe ~/projects/backend-api --note "backend service"
jumbit export --agents >> AGENTS.md
```

```markdown
<!-- jumbit export --agents: project map, ordered by frecency -->
| Path | Description |
|---|---|
| /home/you/projects/backend-api | backend service |
```

**Exit codes and errors**: the agent decision surface — 0 means a result or
success; 1 means no result or a runtime failure ("not found" is not a malfunction,
read stderr to tell them apart); 2 is a usage error; 130 is a user interrupt of
fzf. The full table and the stderr reference are in
[TROUBLESHOOTING.md](TROUBLESHOOTING.md).

**Register as a tool** (a draft JSON schema for tool-registering agents;
skill-loading agents use [.agents/skills/jumbit/SKILL.md](.agents/skills/jumbit/SKILL.md)):

```json
{
  "name": "jumbit_query",
  "description": "Resolve a directory from the user's frecency-ranked directory history. Prefer this over guessing paths or running find. Exit code 1 means no match, not failure.",
  "parameters": {
    "type": "object",
    "properties": {
      "keywords": {
        "type": "array",
        "items": {"type": "string"},
        "description": "One or more keywords; the last anchors the final path component"
      },
      "fuzzy": {
        "type": "boolean",
        "description": "Substring fallback when exact matching misses"
      },
      "limit": {
        "type": "integer",
        "description": "Cap rows returned to control context size"
      }
    },
    "required": ["keywords"]
  }
}
```

Command mapping: run `jumbit query --json [--fuzzy] [--limit N] <keywords...>`,
parse the single-line JSON from stdout, and use `matched_by` to decide the trust
level.

**MCP server**: `jumbit mcp` starts a stdio MCP server (Model Context Protocol,
stdio transport). The tool registration above is automatic for MCP clients: they
read the schema from `tools/list`, with no manual registration. One line for
Claude Code:

```bash
claude mcp add jumbit -- jumbit mcp
```

Other MCP clients use the equivalent JSON:

```json
{
  "mcpServers": {
    "jumbit": {
      "command": "jumbit",
      "args": ["mcp"]
    }
  }
}
```

- Two tools: `jumbit_query` (`keywords`/`fuzzy`/`limit`, returning the same
  single-line JSON array as `query --json`) and `jumbit_export_agents` (no
  arguments, returning the project-map Markdown)
- The `initialize` response carries server instructions (the short narrative of
  when to reach for jumbit, which clients inject into the model's system prompt).
  Protocol versions 2024-11-05 / 2025-03-26 / 2025-06-18 are supported; the
  negotiation rule is to echo a supported version, otherwise answer 2025-06-18
- newline-delimited JSON-RPC 2.0; stdout carries protocol messages only (no logs);
  closing stdin makes it exit cleanly (exit 0)
- The error split matches comparable implementations (atuin mcp): an unknown tool
  or an invalid argument goes through the protocol layer as -32602, while an
  execution failure such as a miss becomes `isError: true` in the result, with the
  same wording as the CLI's stderr ("not found" is not a malfunction)
- The protocol's byte surface is frozen by `scripts/mcp_check.sh` (a CI step), and
  real-client compatibility was tested against the official TypeScript SDK

## Integrations with other tools

jumbit's directory memory is exposed through the CLI for other tools to consume.
The configurations below were verified on real machines (sesh 2.29 / yazi 26.9).

### sesh (tmux session manager)

sesh v2.29.0 offers a `[frecency]` config section that swaps the frecency backend
from zoxide to jumbit wholesale. Write this into `~/.config/sesh/sesh.toml`:

```toml
[frecency]
list_command = "jumbit query --list --score"
query_command = "jumbit query {}"
add_command = "jumbit add {}"
remove_command = "jumbit remove {}"
```

`sesh list -z` lists what jumbit has recorded (descending by score); `sesh connect
<name-or-path>` creates and attaches a session and writes back through
`add_command`, so both the jump decision and the memory accumulation work.

### yazi (terminal file manager)

yazi 26.x supports `--cwd-file` to hand back the directory it exits in, and the
community idiom is a shell wrapper. Add this to `~/.bashrc` or `~/.zshrc`:

```sh
yj() {
	local start="$PWD" tmp cwd
	if [ "$#" -gt 0 ]; then
		start="$(jumbit query "$@")" || return 1
	fi
	tmp="$(mktemp)" || return 1
	yazi "$start" --cwd-file="$tmp"
	if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ]; then
		jumbit add -- "$cwd"
		[ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
	fi
	rm -f -- "$tmp"
}
```

`yj <keyword>` resolves a directory through jumbit as yazi's starting point, and
on exit it feeds the directory you reached back with `jumbit add` and cds there —
the file manager becomes a collector for your directory memory.

## Import

If you use any of the plugins below, you can import their history into jumbit.
The data files are probed by each plugin's standard convention:

```sh
jumbit import <plugin>
```

| Plugin | Command | Data file probing | Data format |
|---|---|---|---|
| atuin | `jumbit import atuin` | read through the `atuin history list` subprocess | `YYYY-MM-DD HH:MM:SS<TAB>path` (subprocess output) |
| autojump | `jumbit import autojump` | `$XDG_DATA_HOME/autojump/autojump.txt`, else `~/.local/share/autojump/autojump.txt` | `rank<TAB>path` (the rank is sigmoid-normalized, matching upstream) |
| fasd | `jumbit import fasd` | `$_FASD_DATA`, else `~/.fasd` | `path\|rank\|timestamp` |
| z | `jumbit import z` | `$_Z_DATA`, else `~/.z` | `path\|rank\|timestamp` |
| z.lua | `jumbit import z.lua` | `$_ZL_DATA`, else `~/.zlua`; falls back to `zlua/zlua.txt` when the main path is missing | `path\|rank\|timestamp` (same parser as z, matching upstream) |
| zsh-z | `jumbit import zsh-z` | `$ZSHZ_DATA`, else as z | `path\|rank\|timestamp` |

Note: when the database is not empty, add `--merge` to import into it (for
example `jumbit import --merge z`); bad rows are reported one by one and never
abort the import.

Note: atuin is read through the `atuin history list` subprocess and its exit code
is not checked (matching upstream), so an atuin-side error yields an empty result
with exit 0 — judge success by stderr.

Note: `import atuin` reads the directory field that atuin captures live alongside
each command (the subprocess runs `atuin history list
--format={time}\t{directory} --print0`, matching upstream). That field only has a
value when the record was produced live by atuin's shell hook; records poured in
from a shell history file with `atuin import bash` and friends carry no directory
information, and atuin fills in the literal `unknown`, so the import produces
meaningless `unknown` entries (byte-identical to upstream, measured 2026-09-27;
atuin 18's `{directory}` template variable itself works, and the output-format
change is unrelated to this import). If your atuin data came from a history-file
import, `import atuin` has no directory information to import.

## How it works

**Frecency ranking.** Each record is three fields — `path / rank /
last_accessed` — and the score is rank (the accumulated visit weight) times a time
decay factor chosen by how long ago `last_accessed` was:

| Time since the last visit | Factor |
|---|---|
| within an hour | ×4.0 |
| within a day | ×2.0 |
| within a week | ×0.5 |
| otherwise | ×0.25 |

**Aging.** When the database's total score **strictly exceeds** `_JB_MAXAGE`
(10000 by default), one global decay runs: every rank is multiplied by
`0.9 × max_age / total`, and any entry whose rank drops below 1 is deleted. Places
you visit often stay; cold ones fade out on their own.

**Persistence.** Data lives in the plaintext file `<data dir>/db.txt`, one entry
per line: `timestamp\trank\tpath` (timestamp is a 10-digit visit time, rank is
fixed-point with two decimals and caps at 9999999.99), which any text tool can
read and hand-edit (breaking it makes the whole database refuse to load and report
the line, see TROUBLESHOOTING). Human annotations live beside it in `notes.tsv`
(`path\tnote`) and never enter db.txt; annotations containing a newline or tab are
rejected. An old binary `db.zo` is converted to plaintext on the first database
write, the original file is kept, and you may delete it once the new database
looks right.

**Keyword matching** (semantics aligned with upstream): the last keyword anchors
the path's final component (no separator may appear between the match and the end
of the path), and the preceding keywords are consumed right-to-left without
overlapping match ranges. Case folding is ASCII-only.

```bash
j backend api   # api lands in the final component, backend is consumed to its left
```

**Query flow**: sort by score descending → keyword filter → glob exclusion
(`_JB_EXCLUDE_DIRS`; a hit is lazily deleted) → existence check. A directory that
no longer exists and has not been visited for over 3 months is lazily deleted at
query time.

## Environment variables

| Variable | Effect | Default |
|---|---|---|
| `_JB_DATA_DIR` | the data directory (an absolute path is required) | `$HOME/.local/share/jumbit` |
| `_JB_ECHO=1` | echo the recorded directory on add | off |
| `_JB_EXCLUDE_DIRS` | colon-separated globs: such paths are blocked on add and lazily removed when a query hits them | the home directory itself |
| `_JB_FZF_OPTS` | extra arguments passed through to fzf | a built-in set |
| `_JB_MAXAGE` | the aging threshold for the database's total score | 10000 |
| `_JB_RESOLVE_SYMLINKS=1` | resolve symlinks on add | off |
| `_JB_DOCTOR=0` | silence the shell-configuration diagnostic (only the bash/zsh/posix templates check) | on |

## Differences from zoxide

- Persistence is the plaintext `db.txt` (`timestamp\trank\tpath`), following the
  plaintext direction of upstream [zoxide#1288](https://github.com/ajeetdsouza/zoxide/pull/1288)
  (jumbit got there before that PR merged); rank is fixed-point with two decimals
  (stored at full precision, read back with two) and annotations live in the side
  file `notes.tsv` rather than the main format (a jumbit extension). It is not
  interoperable with upstream 0.10.0's binary `db.zo`, but is interchangeable with
  a future upstream plaintext format (minus the note column)
- The environment-variable prefix is `_ZO_*` → `_JB_*`; the two can coexist
- Keyword case folding is ASCII-only (upstream folds the full Unicode range)
- `_JB_EXCLUDE_DIRS` glob exclusion does not support `{a,b}` brace expansion
  (treated literally; upstream's glob crate supports it). `*` / `**` / `?` /
  `[...]` match the upstream glob crate's default options (`*` and `**` cross
  separators, `?` and character classes match any single character including
  separators, matching is case-sensitive, and it anchors the whole path).
  `query --exclude` is an exact-path filter with no globbing (matching upstream);
  a repeated `--exclude` lets the last one win (upstream errors out with exit 2:
  `cannot be used multiple times`)
- Linux, macOS (Apple Silicon) and Windows x64 are supported (a CI multi-platform
  matrix: tests, smoke and the byte-frozen surfaces all green). Intel macs are not
  supported (the toolchain's official install script has no darwin-x86_64 branch).
  Platform-specific fzf preview window tweaks are not implemented (the autojump and
  z.lua path probing in import likewise assumes Linux). Windows caveats: the
  colon separator of `_JB_EXCLUDE_DIRS` collides with drive-letter colons (a
  pattern containing `C:` is split wrongly — the workaround is not to start an
  entry with a drive letter), and glob patterns are written with forward slashes
  (a `/` matches a backslash path through separator equivalence; a backslash inside
  a pattern is always an escape)
- The fzf interactive channel (`query --interactive`): selection and `--score`
  output and the exit codes match upstream (a fake-fzf probe matrix compared byte
  for byte). Two wording differences: when fzf is cancelled (its exit code 1)
  jumbit exits 1 silently where upstream prints `no match found`, and the hint for
  an fzf-side failure is the English original with no `zoxide: ` prefix. Also, a
  spawn failure does not distinguish "not installed" from "could not start"
  (upstream does; the process binding does not expose the error class), and both
  report `jumbit: could not find fzf, is it installed?`. The fzf argv lacks
  upstream's `--bind=ctrl-z:ignore,btab:up,tab:down`. On a keyword miss jumbit
  does not start fzf and reports `jumbit: no match found` directly (upstream starts
  fzf first and reports its `could not find fzf` when fzf is missing)
- `edit` is upstream's fzf-driven rank adjustment (0.10.0); jumbit's is
  editor/structured (see the `edit` extension entry). Upstream has announced that
  form is going away (in the #1288 discussion) and jumbit does not follow it
- A read-only `query` does not rewrite the database file: it writes only when the
  query really deletes something (an `_JB_EXCLUDE_DIRS` hit, or the 3-month TTL).
  Upstream's query rewrites the db file on every save. The legacy `db.zo`
  plaintext migration is correspondingly deferred to the first real data change (a
  write command or a lazy delete), and the migrated content is preserved
- `jumbit help <subcommand>` and `jumbit help <unknown>` both print the general
  help and exit 0 (clap's semantics are per-subcommand help, and an unknown one
  reports unrecognized subcommand with exit 2)
- Non-finite ranks: in the plaintext format `inf` is clamped to the upper bound
  and `nan` to the lowest weight (0.01) on import, and a `nan` row encountered on
  read makes the whole database refuse to load and report the line. Upstream
  0.10.0's "non-finite rank poisons the database" problem
  ([zoxide#1280](https://github.com/ajeetdsouza/zoxide/pull/1280)) no longer
  applies under jumbit's plaintext format
- Extensions (no upstream counterpart): `query --json` (a single-line JSON array
  with the `matched_by` evidence field); `query --tsv` (headerless tab-separated
  rows `path\tscore\tlast_accessed\tmatched_by`, same column order as the `--json`
  keys; the path is written verbatim and not escaped, so a path containing a tab
  makes that row's column count ambiguous — a known limitation; the score is the
  shortest form, so NaN/±Infinity come out as the literals
  `NaN`/`Infinity`/`-Infinity` rather than JSON's `null`); `query --limit <n>`
  (truncates `--list`/`--json`/`--tsv` output to the first n rows; `--limit 0`
  gives empty output with exit code 0; a repeat lets the last one win);
  `query --fuzzy` (enabled only when an exact pass finds nothing, and a row
  matches when each keyword is a substring of some path component: no anchoring on
  the final component, order-free, the same component may be reused, and case
  folding is ASCII-only like the main path; it covers the shape of the popular
  upstream feature request [zoxide#1137](https://github.com/ajeetdsouza/zoxide/issues/1137)
  "fall back to fuzzy when nothing matches" (that FR is still open, unimplemented),
  while FR [#388](https://github.com/ajeetdsouza/zoxide/issues/388)'s
  non-contiguous (subsequence) query is not covered: fuzzy is a contiguous
  component substring, so `wrk` does not match `work`); `describe` (human
  annotations on entries, persisted in the database); `export --agents` (the
  project map); `status` (database self-check: data file/size/format/entry
  count/note count/aging threshold; `--json` is a single-line object and `format`
  is `plaintext`/`binary`/`null`; `--check` explicitly runs the O(N) existence
  scan and reports `existing K/N`; a corrupt database exits 1); and `edit`
  (`$VISUAL`/`$EDITOR` on the plaintext database, `--rename` to change a path and
  `--prune` to drop entries that no longer exist)
