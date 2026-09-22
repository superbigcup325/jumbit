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

# VERSION 单一事实源：jumbit.mbt 的 pub const 与 moon.mod version 必须一致
# （moon publish 打包读 moon.mod，用户面 help/mcp serverInfo 读 jumbit.mbt，
#  0.1.1 曾因两边不同步导致 registry 包二进制自报 0.1.0）
MOD_VERSION=$(sed -n 's/^version = "\(.*\)"$/\1/p' moon.mod)
MBT_VERSION=$(sed -n 's/^pub const VERSION : String = "\(.*\)"$/\1/p' jumbit.mbt)
if [ -z "$MOD_VERSION" ] || [ "$MOD_VERSION" != "$MBT_VERSION" ]; then
  echo "✗ 版本不一致：moon.mod=$MOD_VERSION jumbit.mbt=$MBT_VERSION（发版两处同 bump）" >&2
  exit 1
fi

echo "✓ regression 全绿（version=$MOD_VERSION）"
