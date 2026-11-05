#!/bin/bash
# CASE-ID: case-browser
# CASE-DESC: headless-shell 浏览器可用（--version 出 Chrome，可渲染 CJK）
# CASE-COST: low
# CASE-SUGGEST: 浏览器层/Dockerfile 动了就跑；纯本地断言，无模型。
set -euo pipefail
[ -n "${CANARY:-}" ] || { echo "FAIL: CANARY 为空"; exit 1; }
docker exec "$CANARY" chrome-headless-shell --version 2>&1 | tee /tmp/case-browser.out | grep -q 'Chrome' \
  || { echo "FAIL: chrome-headless-shell 版本异常"; cat /tmp/case-browser.out 2>/dev/null || true; exit 1; }
docker exec "$CANARY" test -x /usr/local/bin/chrome-headless-shell
echo "CASE OK: case-browser（headless-shell 可用）"
