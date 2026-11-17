#!/bin/bash
# CASE-ID: case-mcp
# CASE-DESC: open-design MCP 烘焙可用（debug config 见本地二进制；二进制存在；真启动一次，不过只验接线）
# CASE-COST: low
# CASE-SUGGEST: opencode.jsonc/Dockerfile MCP 链动了就跑；无模型调用，25s 内结束。
set -euo pipefail
[ -n "${CANARY:-}" ] || { echo "FAIL: CANARY 为空"; exit 1; }
timeout 180 docker exec "$CANARY" opencode debug config 2>&1 | tee /tmp/case-mcp.out | grep -q 'open-design-mcp' \
  || { echo "FAIL: debug config 未见 open-design-mcp（应为烘焙本地二进制）"; cat /tmp/case-mcp.out 2>/dev/null || true; exit 1; }
docker exec "$CANARY" command -v open-design-mcp \
  || { echo "FAIL: 镜像内无 open-design-mcp 二进制（烘焙丢失）"; exit 1; }
timeout 60 docker exec "$CANARY" timeout 25 open-design-mcp --help 2>&1 | tee /tmp/case-mcp-startup.out | grep -q '\[open-design\]' \
  || { echo "FAIL: open-design-mcp 真启动失败（脏缓存/依赖缺失）"; cat /tmp/case-mcp-startup.out 2>/dev/null || true; exit 1; }
echo "CASE OK: case-mcp（接线+二进制+真启动俱在）"
