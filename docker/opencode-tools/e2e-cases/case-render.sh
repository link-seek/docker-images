#!/bin/bash
# CASE-ID: case-render
# CASE-DESC: headless 浏览器 root 下直调可出图（wrapper 注 --no-sandbox，不显式传 flag）
# CASE-COST: low
# CASE-SUGGEST: 浏览器层/wrapper 动了就跑；本地渲染断言，无模型。
set -euo pipefail
[ -n "${CANARY:-}" ] || { echo "FAIL: CANARY 为空"; exit 1; }
docker exec "$CANARY" sh -c 'rm -f /tmp/case-render.png && /usr/local/bin/chrome-headless-shell --screenshot=/tmp/case-render.png --window-size=800,600 about:blank >/dev/null 2>&1 && test -s /tmp/case-render.png' \
  || { echo "FAIL: root 下直调渲染出图失败（wrapper 未注 flag？）"; exit 1; }
echo "CASE OK: case-render（root 直调出 PNG）"
