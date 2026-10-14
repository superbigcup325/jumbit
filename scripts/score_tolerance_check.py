#!/usr/bin/env python3
"""Score tolerance check for the plaintext-migration window (used by dataset_check.sh only).

Usage: score_tolerance_check.py <jb_query_out> <zo_query_out> <tolerance>
Input: `query --list --score` output (score first on the line, space separated, the rest is the path).
Checks:
  1. both sides carry the same set of paths (a missing or extra one fails)
  2. the same path\'s scores differ by <= tolerance (NaN==NaN counts as equal; a NaN on one side fails)
Exit code 0 = pass, 1 = fail (stderr lists the over-tolerance rows, at most 5).

Once upstream merges #1288 both sides carry two-decimal precision, at which point this script and
dataset_check.sh\'s tolerance logic are deleted together, restoring the byte-level check.
"""
import sys


def load(path):
    out = {}
    with open(path) as f:
        for line in f:
            line = line.rstrip("\n")
            if not line.strip():
                continue
            # line format = right-aligned score + one space + path (the path may be empty or contain
            # spaces; the score itself contains none) — split at the first non-space, keeping trailing spaces
            i = 0
            while i < len(line) and line[i] == " ":
                i += 1
            j = line.find(" ", i)
            if j < 0:
                print(f"malformed line: {line!r}", file=sys.stderr)
                sys.exit(1)
            out[line[j + 1:]] = line[i:j]
    return out


def num(s):
    if s == "NaN":
        return None
    return float(s)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    allow_missing_empty = "--allow-missing-empty" in sys.argv
    allow_zo_nan = "--allow-zo-nan" in sys.argv
    jb, zo, tol = load(args[0]), load(args[1]), float(args[2])
    problems = []
    for p in sorted(set(jb) | set(zo)):
        if p not in jb or p not in zo:
            # empty-path exemption: the plaintext line format cannot express it, so the rescue semantics skip it (spec §1.3)
            if allow_missing_empty and p == "":
                continue
            problems.append(f"path missing on one side: {p!r} (jb={'yes' if p in jb else 'no'} zo={'yes' if p in zo else 'no'})")
            continue
        a, b = num(jb[p]), num(zo[p])
        if a is None or b is None:
            # zo-side NaN exemption: jumbit\'s rescue normalizes NaN to a finite value (spec §1.3)
            if allow_zo_nan and b is None and a is not None:
                continue
            if a is not b and not (a is None and b is None):
                problems.append(f"NaN on one side: {p} jb={jb[p]} zo={zo[p]}")
            continue
        if abs(a - b) > tol:
            problems.append(f"score difference over tolerance: {p} jb={jb[p]} zo={zo[p]} diff={abs(a-b):.4f}")
    if problems:
        for line in problems[:5]:
            print(line, file=sys.stderr)
        if len(problems) > 5:
            print(f"... and {len(problems) - 5} more", file=sys.stderr)
        print(f"FAIL: {len(problems)} problem(s)", file=sys.stderr)
        sys.exit(1)
    sys.exit(0)


if __name__ == "__main__":
    main()
