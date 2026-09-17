#!/usr/bin/env bash
# jumbit MCP 通道协议冻结：release 二进制起 stdio MCP 服务器，喂固定消息序列，
# stdout 逐字节比对（协议信封/工具目录/结果 content/错误码全部在冻结面内）。
#
# 确定性设计（与 golden_check 同思路）：
# - 命中用例的条目来自真实临时目录（工具路不外露 --all，默认链路有 exists
#   检查 + TTL 懒删除，合成的永不存在路径会被过滤/懒删掉），la 取当下
#   （<1h → ×4 档恒定，score 稳定）
# - 随机临时目录路径归一化为 @MCP_TMP@；last_accessed 的 10 位 epoch 归一化
#   为 @EPOCH@；其余字节（信封键序、instructions、工具 schema、错误文案）
#   全部静态
# - 通知不响应、EOF 退出 0 也随序列冻结
#
# 用法：bash scripts/mcp_check.sh [--update]
#   --update  重新生成 scripts/golden-mcp/session.out（变更须人工 diff 审查）
# 依赖：jumbit release 二进制（moon build --release）

set -u
cd "$(dirname "$0")/.."

bin=_build/native/release/build/cmd/main/main.exe
golden=scripts/golden-mcp
mode=check
if [ "${1:-}" = "--update" ]; then
  mode=update
fi
[ -x "$bin" ] || { echo "✗ 缺 $bin（先 moon build --release）" >&2; exit 2; }

tmp=$(mktemp -d /tmp/jumbit-mcp-XXXX)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/alpha" "$tmp/web-app"

# 数据：真实目录 + 新鲜 la（query 的 exists/TTL 链路照常生效且确定性）
printf '%s|1.0|%s\n%s|2.0|%s\n' \
  "$tmp/alpha" "$(date +%s)" "$tmp/web-app" "$(date +%s)" > "$tmp/dataset.z"

# 建库（独立进程 import；空库直灌）
_JB_DATA_DIR="$tmp/db" _Z_DATA="$tmp/dataset.z" "$bin" import z \
  >"$tmp/import.out" 2>"$tmp/import.err"

# 固定 MCP 会话：initialize → initialized(通知，无响应) → tools/list →
# query 命中 → query miss → query 参数非法 → export（无标注 → 空表头）→
# ping（字符串 id）→ 坏 JSON → 未知方法；EOF 关闭
{
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"mcp-check","version":"0"}}}'
  printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'
  printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
  printf '%s\n' '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"jumbit_query","arguments":{"keywords":["alpha"]}}}'
  printf '%s\n' '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"jumbit_query","arguments":{"keywords":["zzznope"]}}}'
  printf '%s\n' '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"jumbit_query","arguments":{"limit":1.5}}}'
  printf '%s\n' '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"jumbit_export_agents"}}'
  printf '%s\n' '{"jsonrpc":"2.0","id":"str-id","method":"ping"}'
  printf '%s\n' 'garbage-not-json'
  printf '%s\n' '{"jsonrpc":"2.0","id":7,"method":"resources/list"}'
} | _JB_DATA_DIR="$tmp/db" "$bin" mcp > "$tmp/session.raw"
code=$?

# 归一化：随机目录路径 + epoch 字面量；update 模式直接落 golden 目录
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
  echo "✓ golden-mcp 已更新（$golden/session.out），请 git diff 人工审查" >&2
  exit 0
fi

if ! diff -u "$golden/session.out" "$tmp/session.out" > "$tmp/session.diff"; then
  echo "✗ MCP 会话字节漂移（详见 $tmp/session.diff）" >&2
  fail=1
else
  echo "✓ MCP 会话字节一致"
  fail=0
fi
want=$(cat "$golden/session.code")
if [ "$code" != "$want" ]; then
  echo "✗ MCP 退出码漂移：want=$want got=$code" >&2
  fail=1
fi
exit $fail
