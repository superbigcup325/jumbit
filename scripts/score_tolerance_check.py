#!/usr/bin/env python3
"""明文迁移窗口期的 score 容差判定（dataset_check.sh 专用）。

用法：score_tolerance_check.py <jb_query_out> <zo_query_out> <tolerance>
输入：`query --list --score` 输出（行首 score，空格分隔，其余为 path）。
判定：
  1. 两侧 path 集合一致（缺失/多出即失败）
  2. 同 path 的 score 数值差 ≤ tolerance（NaN==NaN 视为相等；单侧 NaN 失败）
退出码 0=通过，1=失败（stderr 给出超限明细，最多列 5 条）。

上游合并 #1288 后两侧同为两位小数精度，本脚本与 dataset_check.sh 的容差
逻辑一并删除，恢复全字节级判定。
"""
import sys


def load(path):
    out = {}
    with open(path) as f:
        for line in f:
            line = line.rstrip("\n")
            if not line.strip():
                continue
            # 行格式 = 右对齐 score + 单空格 + path（path 可为空串或含空格，
            # score 本身不含空格）——按首个非空格位切，保留 path 尾随空格
            i = 0
            while i < len(line) and line[i] == " ":
                i += 1
            j = line.find(" ", i)
            if j < 0:
                print(f"格式异常行: {line!r}", file=sys.stderr)
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
            # 空 path 豁免：明文行格式无法表达，救库语义跳过（规格 §1.3）
            if allow_missing_empty and p == "":
                continue
            problems.append(f"路径单侧缺失: {p!r} (jb={'有' if p in jb else '无'} zo={'有' if p in zo else '无'})")
            continue
        a, b = num(jb[p]), num(zo[p])
        if a is None or b is None:
            # zo 侧 NaN 豁免：jumbit 救库把 NaN 归化为有限值（规格 §1.3）
            if allow_zo_nan and b is None and a is not None:
                continue
            if a is not b and not (a is None and b is None):
                problems.append(f"NaN 单侧: {p} jb={jb[p]} zo={zo[p]}")
            continue
        if abs(a - b) > tol:
            problems.append(f"score 差超限: {p} jb={jb[p]} zo={zo[p]} 差={abs(a-b):.4f}")
    if problems:
        for line in problems[:5]:
            print(line, file=sys.stderr)
        if len(problems) > 5:
            print(f"... and {len(problems) - 5} more", file=sys.stderr)
        print(f"FAIL: {len(problems)} 处", file=sys.stderr)
        sys.exit(1)
    sys.exit(0)


if __name__ == "__main__":
    main()
