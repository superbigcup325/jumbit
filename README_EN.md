English | [简体中文](README.md)

# jumbit

A MoonBit rewrite of [zoxide](https://github.com/ajeetdsouza/zoxide): jump to directories in a few keystrokes — jump + Moon**bit**

[![CI](https://github.com/superbigcup325/jumbit/actions/workflows/ci.yml/badge.svg)](https://github.com/superbigcup325/jumbit/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/superbigcup325/jumbit/blob/main/LICENSE)
[![written in MoonBit](https://img.shields.io/badge/written%20in-MoonBit-9B7EDE)](https://www.moonbitlang.com/)
[![platform](https://img.shields.io/badge/platform-Linux-lightgrey)](USAGE.md)
[![rewrite of zoxide](https://img.shields.io/badge/rewrite%20of-zoxide-orange)](https://github.com/ajeetdsouza/zoxide)

## Why

zoxide turns "the places you have cd-ed through" into "one keyword and you are back" via frecency (frequency × time decay) — a staple of the modern shell. jumbit rewrites these long-proven semantics from scratch in MoonBit (a 2026-09 MoonBit hackathon project): no upstream code is carried over, and behavior is aligned item by item with zoxide 0.10.0 — decay factors, keyword matching, aging, exit codes, the fzf channel — backed by million-row, byte-level parity runs against the real upstream binary ([BENCHMARKS.md](BENCHMARKS.md))

On that foundation, jumbit extends directory memory beyond the shell: coding agents are the new "heavy cd users", and jumbit gives them three channels — machine-readable queries, human annotations, and a project map — so an agent opening the workspace immediately knows the directory layout and purpose

## Features

- **Keyword jumping**: `j backend`, `j backend api` — frecency-ranked; the last keyword anchors the final path component, the rest are consumed right-to-left (semantics aligned with upstream)
- **9-shell integration**: nine templates including bash / zsh / fish; directories are recorded on cd, `j`/`ji` (fzf interactive) and completion work out of the box
- **Three agent channels**: byte-stable `--json`/`--tsv` output (with the `matched_by` evidence field), `describe` human annotations persisted in the database, `export --agents` project-map Markdown
- **History migration**: one-command import from z / zsh-z / z.lua / autojump / fasd / atuin — direct pour into an empty database, `--merge` otherwise, bad rows never abort the run
- **Tool ecosystem**: sesh (tmux session manager) can swap its frecency backend wholesale; yazi becomes a directory-memory collector through a wrapper function
- **Data self-check**: `status` shows the database at a glance (entries/notes/format version/aging threshold), `--json` for scripts

## Install

Build from source (requires the [MoonBit toolchain](https://www.moonbitlang.com/), anchored at `moon 0.1.20260904`; CI pins this version for reproducible builds):

```bash
git clone https://github.com/superbigcup325/jumbit && cd jumbit
export PATH="$HOME/.moon/bin:$PATH"   # MoonBit toolchain
moon check && moon test               # optional pre-build self-check
moon build --release
cp _build/native/release/build/cmd/main/main.exe ~/.local/bin/   # or any directory on your PATH
```

Toolchain anchor: CI pins reproducible builds via the `MOONBIT_VERSION` constant in `.github/workflows/ci.yml`; when upgrading the toolchain, bump that constant in the same change and rerun the full verification suite (regression/golden/dataset/chaos/realdata) — the constant is the single source of truth for the version

`superbigcup325/jumbit 0.1.0` is published on mooncakes, but it lags behind main (recent fixes not included); prebuilt binaries are planned

## Quick start

```bash
# 1. Shell integration (bash shown; zsh/fish etc. see USAGE.md)
echo 'eval "$(jumbit init bash)"' >> ~/.bashrc && exec bash
# 2. Work as usual — directories are recorded automatically on cd
cd ~/projects/backend
# 3. Jump back by keyword from anywhere
j backend        # highest-ranked recorded directory matching backend
ji               # interactive jump with fzf (requires fzf)
```

Recording is fully automatic: the shell hook calls `jumbit add` whenever you change directories; to watch it record, `export _JB_ECHO=1`

## Minimal command set

```bash
jumbit add ~/projects/backend        # record a directory (hook-invoked; manual use is fine)
jumbit query backend                 # print the best-matching directory
jumbit query --list --score          # all matches, ranked, with score prefix
jumbit describe ~/projects/backend --note "backend service"   # human annotation (jumbit extension)
jumbit status                        # database self-check (jumbit extension)
jumbit remove ~/projects/backend     # remove from the database
jumbit help                          # every command and flag
```

## Documentation

- [USAGE.md](USAGE.md) — full reference: complete command/flag tables, shell-integration options and `j`/`ji` behavior, agent channels (`--json`/`--tsv`/tool registration schema), sesh/yazi setup, six-plugin import, frecency/aging/matching semantics, environment variables, differences from zoxide (written in Chinese)
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — errors and failures: exit-code table, symptom lookup, stderr message reference, corrupt-database recovery (written in Chinese)
- [BENCHMARKS.md](BENCHMARKS.md) — million-row benchmark against upstream (judge = the real upstream binary)
- Skill-loading agents: [skills/jumbit/SKILL.md](skills/jumbit/SKILL.md)

## License

MIT License. A semantic rewrite based on [zoxide](https://github.com/ajeetdsouza/zoxide) (MIT); the license file carries the original copyright notice
