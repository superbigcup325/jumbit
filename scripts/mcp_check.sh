#!/usr/bin/env bash
# jumbit MCP channel protocol freeze: start the release binary's stdio MCP server, feed it a fixed sequence,
# and compare stdout byte for byte (protocol envelope, tool directory, result content and error codes are all inside the frozen surface).
#
# Determinism design (the same approach as golden_check):
# - a matching case's entry comes from a real temporary directory (the tool path does not expose --all, so the default chain has the exists
#   check plus TTL lazy deletion, and a synthetic never-existing path would be filtered or lazily deleted), and la is set to now
#   (the <1h bucket is a constant ×4, so the score is stable)
# - the random temporary directory path is normalized to @MCP_TMP@ and last_accessed's 10-digit epoch to
#   @EPOCH@; every other byte (envelope key order, instructions, tool schema, error wording)
#   is static
# - notifications getting no reply, and exit 0 on EOF, are frozen with the sequence too
#
# Usage: bash scripts/mcp_check.sh [--update]
#   --update  regenerate scripts/golden-mcp/session.out (any change needs a hand-reviewed diff)
# Depends on: the jumbit release binary (moon build --release)

set -u
cd "$(dirname "$0")/.."

bin=_build/native/release/build/cmd/jumbit/jumbit.exe
golden=scripts/golden-mcp
mode=check
if [ "${1:-}" = "--update" ]; then
  mode=update
fi
[ -x "$bin" ] || { echo "✗ $bin is missing (run moon build --release first)" >&2; exit 2; }

tmp=$(mktemp -d /tmp/jumbit-mcp-XXXX)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/alpha" "$tmp/web-app"

# Data: a real directory plus a fresh la (query's exists/TTL chain still applies, deterministically)
printf '%s|1.0|%s\n%s|2.0|%s\n' \
  "$tmp/alpha" "$(date +%s)" "$tmp/web-app" "$(date +%s)" > "$tmp/dataset.z"

# Build the database (import in a separate process; a direct pour into an empty one)
_JB_DATA_DIR="$tmp/db" _Z_DATA="$tmp/dataset.z" "$bin" import z \
  >"$tmp/import.out" 2>"$tmp/import.err"

# The fixed MCP session: initialize → initialized (a notification, no reply) → tools/list →
# query hit → query miss → query with an invalid argument → export (no annotations → empty header) →
# ping (a string id) → malformed JSON → unknown method; then EOF closes it
{
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"mcp-check","version":"0"}}}'
  printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'
  printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
  printf '%s\n' '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"jumbit_query","arguments":{"keywords":["alpha"]}}}'
  printf '%s\n' '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"jumbit_query","arguments":{"keywords":["zzznope"]}}}'
  printf '%s\n' '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"jumbit_query","arguments":{"keywords":["alpha"],"limit":1.5}}}'
  printf '%s\n' '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"jumbit_export_agents"}}'
  printf '%s\n' '{"jsonrpc":"2.0","id":"str-id","method":"ping"}'
  printf '%s\n' 'garbage-not-json'
  printf '%s\n' '{"jsonrpc":"2.0","id":7,"method":"resources/list"}'
  printf '%s\n' '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"jumbit_query","arguments":{}}}'
} | _JB_DATA_DIR="$tmp/db" "$bin" mcp > "$tmp/session.raw"
code=$?

# Normalization: the random directory path and epoch literals; update mode writes straight into the golden directory
outdir="$tmp"
if [ "$mode" = update ]; then
  mkdir -p "$golden"
  outdir="$golden"
  echo 0 > "$golden/session.code"
fi
sed -E -e "s|$tmp|@MCP_TMP@|g" -e 's/[0-9]{10}/@EPOCH@/g' \
  "$tmp/session.raw" > "$outdir/session.out"
echo "$code" > "$tmp/session.code"

if [ "$mode" = update ]; then
  echo "✓ golden-mcp updated ($golden/session.out); review with git diff" >&2
  exit 0
fi

if ! diff -u "$golden/session.out" "$tmp/session.out" > "$tmp/session.diff"; then
  echo "✗ MCP session bytes drifted (see $tmp/session.diff)" >&2
  fail=1
else
  echo "✓ MCP session bytes match"
  fail=0
fi
want=$(cat "$golden/session.code")
if [ "$code" != "$want" ]; then
  echo "✗ MCP exit code drifted: want=$want got=$code" >&2
  fail=1
fi
exit $fail
