#!/usr/bin/env bash
# jumbit 回归基线：任一失败即退出非零。提交前必跑。
set -euo pipefail
export PATH="$HOME/.moon/bin:$PATH"
cd "$(dirname "$0")/.."

echo "== moon check --deny-warn =="
moon check --deny-warn

echo "== moon test =="
moon test

echo "== moon fmt --check =="
moon fmt --check

echo "== moon info（API 面冻结）=="
moon info
if ! git diff --exit-code -- '*.mbti'; then
  echo "✗ .mbti 有未提交变更：API 面变动请 review 后提交" >&2
  exit 1
fi

echo "✓ regression 全绿"
