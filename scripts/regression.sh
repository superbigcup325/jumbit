#!/usr/bin/env bash
# jumbit regression baseline: any failure exits non-zero. Run it before committing.
set -euo pipefail
export PATH="$HOME/.moon/bin:$PATH"
cd "$(dirname "$0")/.."

echo "== moon check --deny-warn =="
moon check --deny-warn

echo "== moon test =="
moon test

echo "== moon fmt --check =="
moon fmt --check

echo "== moon info (API surface freeze) =="
moon info
if ! git diff --exit-code -- '*.mbti'; then
  echo "✗ .mbti has uncommitted changes: review the API-surface change, then commit it" >&2
  exit 1
fi

# VERSION single source of truth: the pub const in jumbit.mbt and moon.mod's version must agree
# (moon publish reads moon.mod when packaging; user-facing help / mcp serverInfo read jumbit.mbt,
#  and in 0.1.1 the two drifted, so the registry package's binary reported 0.1.0)
MOD_VERSION=$(sed -n 's/^version = "\(.*\)"$/\1/p' moon.mod)
MBT_VERSION=$(sed -n 's/^pub const VERSION : String = "\(.*\)"$/\1/p' jumbit.mbt)
if [ -z "$MOD_VERSION" ] || [ "$MOD_VERSION" != "$MBT_VERSION" ]; then
  echo "✗ version mismatch: moon.mod=$MOD_VERSION jumbit.mbt=$MBT_VERSION (bump both together on release)" >&2
  exit 1
fi

echo "✓ regression all green (version=$MOD_VERSION)"
