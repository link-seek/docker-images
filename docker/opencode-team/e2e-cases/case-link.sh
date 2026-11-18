#!/bin/bash
# CASE-ID: case-link
# CASE-DESC: 全链路：pod 内 agent-browser 经 CDP 连 browserless（example.com 外网可达）
# CASE-COST: medium
set -euo pipefail
[ -n "${K8S_EXEC:-}" ] || { echo "FAIL: K8S_EXEC 为空（fine-test.sh 未导出）"; exit 1; }
TOKEN="${TOKEN:-dummy-preflight}"
WS_URL="${WS_URL:-ws://browserless:3000/chromium?token=$TOKEN}"
$K8S_EXEC agent-browser connect "$WS_URL" \
  && echo "CDP CONNECT OK" || { echo "FAIL: agent-browser connect 不通（$WS_URL）"; exit 1; }
$K8S_EXEC agent-browser open https://example.com \
  && echo "OPEN OK" || { echo "FAIL: open 失败"; exit 1; }
$K8S_EXEC agent-browser snapshot | grep -qi "example" \
  && echo "SNAPSHOT OK" || { echo "FAIL: snapshot 无预期内容"; exit 1; }
$K8S_EXEC agent-browser screenshot /tmp/fine-team-shot.png \
  && echo "SCREENSHOT OK" || { echo "FAIL: screenshot 失败"; exit 1; }
$K8S_EXEC agent-browser close \
  && echo "CLOSE OK" || { echo "FAIL: close 失败"; exit 1; }
echo "CASE OK: case-link（agent-browser CDP→browserless 全链路）"
