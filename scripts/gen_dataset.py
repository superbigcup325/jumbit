#!/usr/bin/env python3
"""Synthetic jumbit/zoxide comparison dataset.

Fixed seed, reproducible, stdlib-only. Three formats:
- the z family (shared by z/fasd/zsh-z/z.lua): `path|rank|last_accessed`
- autojump：`rank\\tpath`
- atuin: a record stream of `YYYY-MM-DD HH:MM:SS\\tpath` ` (the NUL separation is added by the comparison script)

Distribution design:
- the path pool = real local directories sampled (find ~, depth and count limited) plus hand-written boundary paths
- visit frequency follows a Zipf distribution (a few directories take most visits, imitating a real footprint)
- timestamps: 70% recent (exponential), 20% within two years, 10% stale (exercising the x0.25 bucket and lazy deletion),
  plus the exact decay-bucket boundaries (now-1h/-1d/-1w/-30d)
- rank values include regular floats and boundary literals (nan/inf/+5/007/1e3 and so on: the comparison surface for both sides' parsing semantics)
- a few deterministic bad rows (to check that bad-row reporting on stderr matches byte for byte)

Usage: gen_dataset.py --format z --lines 20000 --out /tmp/ds/z.txt [--seed N]
"""

from __future__ import annotations

import argparse
import itertools
import os
import random
import subprocess
from datetime import datetime, timezone
from pathlib import Path

SEED = 20260908
# A fixed reference time (around the dataset's creation date): every timestamp is generated relative to it, keeping the same seed byte-reproducible.
# Note: as real time passes the "recent" entries grow stale, which is harmless here (both sides see the same data)
NOW = 1788824275

# Hand-written boundary paths: Unicode / spaces / pipes / dot segments / overlong / hyphens (the z family allows | in a path)
EDGE_PATHS = [
    "/home/用户/博客",
    "/opt/with space/dir name",
    "/opt/pipe|in|path",
    "/data/.hidden/.config",
    "/data/trailing.dots...",
    "/data/" + "l" * 200 + "-long-component",
    "/data/a/b/c/d/e/f/deep-nest",
    "/data/mixed-中文-한국어-عربي",
    "/data/-dash-start",
    "/data/number-123-456",
]


def real_dir_pool(max_depth: int, limit: int) -> list[str]:
    """Sample real local directories; if find fails or returns nothing, fall back to the boundary pool alone."""
    home = os.path.expanduser("~")
    try:
        out = subprocess.run(
            ["find", home, "-maxdepth", str(max_depth), "-type", "d"],
            capture_output=True,
            text=True,
            timeout=20,
            check=True,
        ).stdout.splitlines()
    except Exception:
        return []
    # filter obvious noise: overlong paths, or ones containing a newline, cannot occur and find will not yield them
    pool = [p for p in out if len(p) < 250 and p != home][:limit]
    return pool


def synthetic_pool(n: int) -> list[str]:
    """Synthesize a unique-path pool (for the performance scale set): a component word pool plus a six-digit index keeps all n distinct.

    The final component comes from a 10-word pool so the keyword-query scenario hits about 1/10 of the entries.
    """
    words = ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot",
             "golf", "hotel", "india", "juliet", "kilo", "lima"]
    tails = ["src", "docs", "build", "test", "tools", "bin", "lib", "conf", "data", "log"]
    return [
        f"/opt/{words[i % len(words)]}/{words[(i // len(words)) % len(words)]}-{i:06d}/{tails[i % len(tails)]}"
        for i in range(n)
    ]


def zipf_pick(rng: random.Random, pool: list[str]) -> str:
    """A 1/rank power-law sample: a few paths take the vast majority of hits."""
    rank = rng.paretovariate(1.2)  # heavy tail
    idx = min(int(rank * 8), len(pool) - 1)
    return pool[idx]


def pick_offset(rng: random.Random) -> int:
    """A second offset from now: the time-decay distribution plus the exact bucket boundaries."""
    roll = rng.random()
    if roll < 0.10:
        # the exact bucket boundaries (1h/1d/1w/30d ago): where both sides switch decay factor
        return rng.choice([3600, 86400, 604800, 2592000])
    if roll < 0.75:
        # recent: exponential, mean 7 days
        return int(rng.expovariate(1 / (7 * 86400)))
    if roll < 0.95:
        # within two years
        return rng.randint(86400, 2 * 365 * 86400)
    # the stale long tail (>3 months, exercising the x0.25 bucket and the lazy-deletion boundary)
    return rng.randint(90 * 86400, 5 * 365 * 86400)


def unique_offsets(rng: random.Random, n: int) -> list[int]:
    """n distinct second offsets: sample from the distribution, then sort and de-duplicate (adjacent +1 keeps them unique).
    Unique timestamps keep scores almost free of ties: different sort algorithms order equal scores
    differently, so they could never match byte for byte; uniqueness is the precondition for a stable comparison."""
    offsets = sorted(pick_offset(rng) for _ in range(n))
    for i in range(1, n):
        if offsets[i] <= offsets[i - 1]:
            offsets[i] = offsets[i - 1] + 1
    rng.shuffle(offsets)
    return offsets


RANK_POOL = [
    "1", "2.5", "0.5", "10", "100", "3.14159",
    "-2", "-0.75", "0", "007", "+5", "1e3", "-0",
    "0.1", "0.2", "0.3",  # float-precision-sensitive values
    "123.456", "99999",
]
# the nan/inf family: after parsing, bit-pattern differences (payload, sign) introduce tie-order
# divergence, so they stay out of the byte-level comparison; their display/sort semantics are locked by unit tests against upstream's total_cmp source.
# 1e308 likewise: once the inf total is clamped, everything ties at 9999.0.
RANK_EDGE = ["nan", "NaN", "inf", "-inf", "infinity", "INF", "1e308"]


def pick_rank(rng: random.Random, allow_edge: bool) -> str:
    if allow_edge and rng.random() < 0.02:
        return rng.choice(RANK_EDGE)
    return rng.choice(RANK_POOL)


BAD_Z_LINES = [
    "nobar",
    "|1.5|100",
    "/a|x|100",
    "/a|1.5|y",
    "/a|1.5|-5",
    "",
    "1.5|100",
]
BAD_AJ_LINES = ["bad-line", "", "\t", "x\t", "1.5|no-tab"]


def gen_z(
    rng: random.Random, lines: int, pool: list[str], now: int, allow_edge: bool,
    path_iter=None,
) -> list[str]:
    offsets = unique_offsets(rng, lines)
    out = []
    for i in range(lines):
        if rng.random() < 0.01:
            out.append(rng.choice(BAD_Z_LINES))
            continue
        path = next(path_iter) if path_iter is not None else zipf_pick(rng, pool)
        if path == "":
            continue
        out.append(f"{path}|{pick_rank(rng, allow_edge)}|{now - offsets[i]}")
    return out


def gen_autojump(
    rng: random.Random, lines: int, pool: list[str], now: int, allow_edge: bool,
) -> list[str]:
    del now  # autojump does not store a time
    out = []
    for _ in range(lines):
        if rng.random() < 0.01:
            out.append(rng.choice(BAD_AJ_LINES))
            continue
        path = zipf_pick(rng, pool)
        if path == "":
            continue
        # autojump weights are arbitrary floats and its time is not stored (the import side sigmoid-normalizes and sets last_accessed=0)
        out.append(f"{pick_rank(rng, allow_edge)}\t{path}")
    return out


def fmt_atuin_time(epoch: int) -> str:
    return datetime.fromtimestamp(epoch, tz=timezone.utc).strftime("%Y-%m-%d %H:%M:%S")


def gen_atuin_records(
    rng: random.Random, lines: int, pool: list[str], now: int, allow_edge: bool,
) -> list[str]:
    """An atuin command-sequence record: lots of consecutive repeats (exercising the consecutive-folding semantics)."""
    del allow_edge  # an atuin rank is always 1.0, so there are no rank literals
    offsets = unique_offsets(rng, lines)
    out = []
    i = 0
    while i < lines:
        path = zipf_pick(rng, pool)
        if path == "":
            i += 1
            continue
        stay = min(rng.randint(1, 20), lines - i)  # how many commands stay in one directory
        for _ in range(stay):
            if rng.random() < 0.02:
                # timestamp boundaries (leap days and pre-epoch values are validated by the parsing side)
                ts = rng.choice([
                    "2024-02-29 00:00:00", "2023-02-29 00:00:00",
                    "1969-12-31 23:59:59",
                ])
            else:
                ts = fmt_atuin_time(now - offsets[i])
            out.append(f"{ts}\t{path}")
            i += 1
            if i >= lines:
                break
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--format", required=True, choices=["z", "autojump", "atuin"])
    ap.add_argument("--lines", type=int, default=20000)
    ap.add_argument("--out", required=True)
    ap.add_argument("--seed", type=int, default=SEED)
    ap.add_argument("--max-depth", type=int, default=4)
    ap.add_argument("--now", type=int, default=NOW, help="the reference timestamp in epoch seconds")
    ap.add_argument("--rank-edge", action="store_true",
                    help="mix in nan/inf/1e308 boundary ranks (content-level comparison only, never byte-level)")
    ap.add_argument("--unique-paths", type=int, default=0,
                    help="use the synthesized unique-path pool instead (performance scale set, --format z only): paths rotate line by line,"
                         "about lines/N times each (triggering dedup), never stacked on the real local pool or Zipf")
    args = ap.parse_args()

    if args.unique_paths and args.format != "z":
        ap.error("--unique-paths only supports --format z")

    rng = random.Random(args.seed)
    now = args.now

    path_iter = None
    if args.unique_paths:
        order = synthetic_pool(args.unique_paths)
        rng.shuffle(order)
        path_iter = itertools.cycle(order)
        pool = order  # for the summary at the end only
    else:
        pool = real_dir_pool(args.max_depth, 800) + EDGE_PATHS
        if not pool:
            pool = list(EDGE_PATHS)

    if args.format == "z":
        lines_ = gen_z(rng, args.lines, pool, now, args.rank_edge, path_iter)
    elif args.format == "autojump":
        lines_ = gen_autojump(rng, args.lines, pool, now, args.rank_edge)
    else:
        lines_ = gen_atuin_records(rng, args.lines, pool, now, args.rank_edge)

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    if args.format == "atuin":
        # atuin --print0 semantics: records NUL-separated with a trailing NUL (not line text!)
        out.write_bytes("\x00".join(lines_).encode("utf-8") + b"\x00")
    else:
        out.write_text("\n".join(lines_) + "\n", encoding="utf-8")
    print(f"{args.format}: {len(lines_)} lines -> {out} (seed={args.seed}, pool={len(pool)})")


if __name__ == "__main__":
    main()
