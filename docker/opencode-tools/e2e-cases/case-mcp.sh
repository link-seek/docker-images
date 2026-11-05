#!/bin/bash
# CASE-ID: case-mcp
# CASE-DESC: open-design MCP 接线可用（opencode mcp list 见 open-design）
# CASE-COST: low
# CASE-SUGGEST: opencode.jsonc/MCP 链动了就跑；npx 首启现下，宽限 180s，无模型调用。
set -euo pipefail
[ -n "${CANARY:-}" ] || { echo "FAIL: CANARY 为空"; exit 1; }
timeout 180 docker exec "$CANARY" opencode mcp list 2>&1 | tee /tmp/case-mcp.out | grep -q 'open-design' \
  || { echo "FAIL: mcp list 未见 open-design"; cat /tmp/case-mcp.out 2>/dev/null || true; exit 1; }
echo "CASE OK: case-mcp（open-design 接线可见）"
