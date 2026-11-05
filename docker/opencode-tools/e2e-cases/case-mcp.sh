#!/bin/bash
# CASE-ID: case-mcp
# CASE-DESC: open-design MCP 接线可用（debug config 见 open-design；mcp list 只反映运行时需 session，裸容器恒空，不用它）
# CASE-COST: low
# CASE-SUGGEST: opencode.jsonc/MCP 链动了就跑；只读合并后配置，无模型调用。
set -euo pipefail
[ -n "${CANARY:-}" ] || { echo "FAIL: CANARY 为空"; exit 1; }
timeout 180 docker exec "$CANARY" opencode debug config 2>&1 | tee /tmp/case-mcp.out | grep -q 'open-design' \
  || { echo "FAIL: debug config 未见 open-design"; cat /tmp/case-mcp.out 2>/dev/null || true; exit 1; }
echo "CASE OK: case-mcp（open-design 接线可见）"
