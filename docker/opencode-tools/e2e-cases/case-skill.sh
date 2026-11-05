#!/bin/bash
# CASE-ID: case-skill
# CASE-DESC: skill 文件随镜像可用（含开题工具 prepare_open_design_brief）
# CASE-COST: low
# CASE-SUGGEST: Dockerfile skill 安装链、AGENTS.md 动了就跑；纯文件断言，无模型。
set -euo pipefail
[ -n "${CANARY:-}" ] || { echo "FAIL: CANARY 为空"; exit 1; }
docker exec "$CANARY" test -f /root/.agents/skills/open-design/SKILL.md
docker exec "$CANARY" grep -q prepare_open_design_brief /root/.agents/skills/open-design/SKILL.md
echo "CASE OK: case-skill（skill 文件 + 开题工具引用俱在）"
