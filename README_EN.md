English | [简体中文](README.md)

# jumbit

A MoonBit rewrite of [zoxide](https://github.com/ajeetdsouza/zoxide): jump to directories in a few keystrokes.

[![CI](https://github.com/superbigcup325/jumbit/actions/workflows/ci.yml/badge.svg)](https://github.com/superbigcup325/jumbit/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/superbigcup325/jumbit/blob/main/LICENSE)
[![written in MoonBit](https://img.shields.io/badge/written%20in-MoonBit-9B7EDE)](https://www.moonbitlang.com/)
[![platform](https://img.shields.io/badge/platform-Linux-lightgrey)](https://github.com/superbigcup325/jumbit/blob/main/README_EN.md#differences-from-zoxide)
[![rewrite of zoxide](https://img.shields.io/badge/rewrite%20of-zoxide-orange)](https://github.com/ajeetdsouza/zoxide)

jumbit records the directories you visit, ranks them by frecency (frequency × time decay), and jumps back with a few keywords:

```bash
j projects      # highest-ranked recorded directory matching projects
j backend api   # multiple keywords: api anchors the final path component, backend is consumed leftward
```

## Install

Currently built from source (requires the [MoonBit toolchain](https://www.moonbitlang.com/)):

```bash
git clone https://github.com/superbigcup325/jumbit && cd jumbit
export PATH="$HOME/.moon/bin:$PATH"   # MoonBit toolchain
moon check && moon test               # optional pre-build self-check
moon build --release
# artifact: _build/native/release/build/cmd/main/main.exe — copy it onto your PATH
```

Toolchain anchor: `moon 0.1.20260904` (moonc v0.10.12) — CI pins this version for reproducible builds (the `MOONBIT_VERSION` constant in `.github/workflows/ci.yml`), and every gate in this repository is verified against it. When upgrading the toolchain, bump that constant in the same change and rerun the full verification suite (regression/golden/dataset/chaos/realdata). The constant is the single source of truth for the version

Note: publishing to mooncakes and providing prebuilt binaries are planned

## Quick start

```bash
# 1. Shell integration (bash shown; zsh/fish see "Shell integration")
echo 'eval "$(jumbit init bash)"' >> ~/.bashrc && exec bash
# 2. Work as usual — directories are recorded automatically on cd
cd ~/projects/backend
# 3. Jump back by keyword from anywhere
j backend        # highest-ranked recorded directory matching backend
ji               # interactive jump with fzf
```

Recording is fully automatic: the shell hook calls `jumbit add` whenever you change directories; to watch it record, `export _JB_ECHO=1`

## Usage

```bash
jumbit add ~/projects/backend        # record a directory (hook-invoked; manual use is fine)
jumbit add --score 3.5 ~/projects    # specify this visit's weight increment
jumbit query backend                 # print the best-matching directory
jumbit query --list --score          # all matches, ranked, with score prefix
jumbit query --interactive           # interactive selection with fzf
jumbit query --all --exclude ~/tmp   # skip existence checks / exclude directories
jumbit query --json                  # all matches as a single-line JSON array (agent channel)
jumbit query --tsv                   # tab-separated data rows (agent channel, jumbit extension)
jumbit query --list --limit 5        # first 5 rows (applies to list-style output, jumbit extension)
jumbit query --fuzzy blog            # component-substring fallback when exact matching misses (jumbit extension)
jumbit describe ~/projects/backend --note "backend service"   # human annotation (jumbit extension)
jumbit export --agents               # project map as Markdown (jumbit extension)
jumbit remove ~/projects/backend     # remove from the database
jumbit help
```

## Shell integration

```bash
# bash: add to ~/.bashrc
eval "$(jumbit init bash)"
# zsh: ~/.zshrc; fish: ~/.config/fish/config.fish with `jumbit init fish | source`
# elvish / nushell / posix / powershell / tcsh / xonsh are also supported, same pattern

j backend        # jump (with completion)
ji               # interactive jump with fzf
```

Options: `--cmd C` renames the command (default `j`, e.g. `--cmd=cd`), `--hook pwd|prompt|none` selects the recording trigger (default `pwd`), `--no-cmd` emits internal functions only

## For agents

jumbit's directory memory feeds coding agents as well as shells. Three channels:

**Machine-readable queries**: `query --json` / `--tsv` are made for agent scripts; `--limit N` caps the number of returned rows to control context overhead:

```bash
jumbit query --json backend
```

```json
[{"path":"/home/you/projects/backend-api","score":8,"last_accessed":1789054423,"matched_by":"exact"}]
```

- Fixed key order `path, score, last_accessed, matched_by`, single-line array, byte-stable
- `last_accessed` is epoch seconds; `score` is the shortest float representation (NaN/±Infinity become `null`, the JSON numeric domain)
- `matched_by` is an evidence field: `exact` (keyword match) or `fuzzy` (substring fallback via `--fuzzy`); agents can use it to decide how much to trust a result
- `--tsv` emits headerless tab-separated rows in the same column order as the JSON keys, suitable for tabular tools:

```
/home/you/projects/backend-api	8	1789054423	exact
```

**Project map**: `describe` attaches human annotations to frequently used directories (persisted in the database), and `export --agents` renders them as a Markdown table — append it to your AGENTS.md and any agent opening the workspace learns the project layout and purpose:

```bash
jumbit describe ~/projects/backend-api --note "backend service"
jumbit export --agents >> AGENTS.md
```

```markdown
<!-- jumbit export --agents：项目地图，按常用度（frecency）降序 -->
| 路径 | 说明 |
|---|---|
| /home/you/projects/backend-api | backend service |
```

(The comment and table header above are emitted by the tool as shown.)

## Integration with other tools

jumbit's directory memory is exposed to other tools through the CLI surface. All configurations below were verified on real machines (sesh 2.29 / yazi 26.9)

### sesh (tmux session manager)

sesh v2.29.0 added a `[frecency]` section that swaps the frecency backend from zoxide to jumbit wholesale. Put this into `~/.config/sesh/sesh.toml`:

```toml
[frecency]
list_command = "jumbit query --list --score"
query_command = "jumbit query {}"
add_command = "jumbit add {}"
remove_command = "jumbit remove {}"
```

`sesh list -z` lists jumbit records (ranked); `sesh connect <name-or-path>` creates and attaches a session, and connecting writes usage back through `add_command` — jump decisions and memory accumulation feed each other

### yazi (terminal file manager)

yazi 26.x reports the exit directory via `--cwd-file`; the community convention is a shell wrapper function. Add to `~/.bashrc` or `~/.zshrc`:

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

`yj <keywords>` resolves the starting directory through jumbit and enters the file manager; on exit it automatically `jumbit add`s the landing directory and cds to it — the file manager becomes a collector for directory memory

## Import

If you use any of the plugins below, import their history into jumbit. Data files are auto-detected per each plugin's standard conventions:

```sh
jumbit import <plugin>
```

| Plugin | Command | Data file detection |
|---|---|---|
| atuin | `jumbit import atuin` | read via the `atuin history list` subprocess |
| autojump | `jumbit import autojump` | `$XDG_DATA_HOME/autojump/autojump.txt`, default `~/.local/share/autojump/autojump.txt` |
| fasd | `jumbit import fasd` | `$_FASD_DATA`, else `~/.fasd` |
| z | `jumbit import z` | `$_Z_DATA`, else `~/.z` |
| z.lua | `jumbit import z.lua` | `$_ZL_DATA`, else `~/.zlua`; falls back to `zlua/zlua.txt` when the main path is missing |
| zsh-z | `jumbit import zsh-z` | `$ZSHZ_DATA`, else same as z |

Note: when the database is non-empty, add `--merge` (e.g. `jumbit import --merge z`); bad rows are reported one by one without aborting the import

## How it works

**Frecency ranking.** Each record holds `path / rank / last_accessed`; score = rank (accumulated visit weight) × time-decay factor, tiered by the age of `last_accessed`:

| Since last visit | Factor |
|---|---|
| within 1 hour | ×4.0 |
| within 1 day | ×2.0 |
| within 1 week | ×0.5 |
| otherwise | ×0.25 |

**Aging.** When the database total **strictly exceeds** `_JB_MAXAGE` (default 10000), a global decay runs once: every rank is multiplied by `0.9 × max_age / total`, and entries whose rank drops below 1 are removed — frequently visited places stay, cold ones fade out naturally

**Keyword matching** (semantics aligned with upstream): the last keyword anchors to the final path component (no separator may appear between the hit and the end of the path), the remaining keywords are consumed right-to-left with non-overlapping hits; case normalization is ASCII-only

```bash
j backend api   # api lands on the final component, backend is consumed to its left
```

**Query pipeline**: rank-descending → keyword filter → glob exclusion (a hit lazy-deletes) → existence check; missing directories unvisited for over 3 months are lazily deleted at query time

## Environment variables

| Variable | Purpose | Default |
|---|---|---|
| `_JB_DATA_DIR` | data directory (must be absolute) | `$HOME/.local/share/jumbit` |
| `_JB_ECHO=1` | echo recorded directories on add | off |
| `_JB_EXCLUDE_DIRS` | colon-separated globs; matched directories are never recorded | the home directory itself |
| `_JB_FZF_OPTS` | custom arguments passed through to fzf | built-in argument set |
| `_JB_MAXAGE` | database total-score aging threshold | 10000 |
| `_JB_RESOLVE_SYMLINKS=1` | resolve symlinks on add | off |

## Differences from zoxide

- Persistence uses a custom binary format (version number + length-prefixed entries), **not interoperable** with upstream `db.zo`; entries carry a note annotation since v2 (jumbit extension), and old v1 databases are read without migration
- Environment variable prefix `_ZO_*` → `_JB_*`; both can coexist
- Keyword case normalization is ASCII-only (upstream covers full Unicode)
- Glob exclusion does not support `{a,b}` brace expansion; `**` is treated as two `*`s and does not cross separators (the upstream glob crate treats `**` as a recursive wildcard); `*`/`?`/`[...]` semantics are aligned
- Linux only; the fzf preview-window platform customization is not implemented (import's autojump/z.lua path detection likewise follows Linux semantics)
- fzf interactive channel (`query --interactive`): selection/`--score` output and exit codes are aligned with upstream (byte-compared via a fake-fzf probe matrix); two message differences — on fzf cancel (its exit code 1) jumbit exits 1 silently while upstream reports `no match found`; fzf's own failure messages are the English originals without the `zoxide: ` prefix. Also, spawn failures do not distinguish "not installed" from "cannot launch" (upstream distinguishes; the process binding exposes no error category), uniformly reporting `could not find fzf, is it installed?`
- Not ported: the `edit` subcommand
- Known issue (identical to upstream 0.10.0): non-finite rank poisoning — `import` accepts `inf`/`nan` literals and overflow-saturated inf values as rank, and `add --score` accepts them too; aging with `total=inf` zeroes the factor and evicts every other entry, aging with `total=NaN` stalls permanently, all with exit code 0 and no warning. Upstream fix [ajeetdsouza/zoxide#1280](https://github.com/ajeetdsouza/zoxide/pull/1280) is unmerged; jumbit will follow once it lands
- Extensions (absent upstream): `query --json` (single-line JSON array with the `matched_by` evidence field), `query --tsv` (headerless tab-separated rows `path\tscore\tlast_accessed\tmatched_by`, column order identical to the `--json` key order; path passes through unescaped — a path containing a tab makes that row's column count ambiguous, a known limitation; score uses the shortest representation, with NaN/±Infinity emitted as `NaN`/`Infinity`/`-Infinity` rather than JSON's `null`), `query --limit <n>` (first-n truncation for `--list`/`--json`/`--tsv` output, `--limit 0` being empty output with exit code 0; a repeated occurrence lets the last one win), `query --fuzzy` (active only when exact matching misses; a keyword matches if it is a substring of some path component — not restricted to the final component, unordered, same component allowed; case normalization identical to the main path, ASCII-only), `describe` (human annotations on entries, persisted in the database) and `export --agents` (project map)

## License

MIT License. A semantic rewrite based on [zoxide](https://github.com/ajeetdsouza/zoxide) (MIT); the license file carries the original copyright notice
