#!/bin/bash
# CASE-ID: case-browser
# CASE-DESC: sidecar 浏览器经 CDP 可达（open+snapshot 往返，无模型）
# CASE-COST: low
# CASE-SUGGEST: sidecar/kit CDP 链动了就跑；纯 CDP 断言。
set -euo pipefail
[ -n "${K8S_EXEC:-}" ] || { echo "FAIL: K8S_EXEC 为空（fine-test.sh 未导出）"; exit 1; }
CDP="$($K8S_EXEC printenv BROWSER_CDP_URL 2>/dev/null || true)"
[ -n "$CDP" ] || { echo "FAIL: 容器内 BROWSER_CDP_URL 为空（部署侧没给 sidecar 地址）"; exit 1; }
$K8S_EXEC agent-browser --cdp "$CDP" open about:blank > /tmp/case-browser-open.out 2>&1 \
  || { echo "FAIL: CDP open 失败"; cat /tmp/case-browser-open.out 2>/dev/null || true; exit 1; }
$K8S_EXEC agent-browser --cdp "$CDP" snapshot > /tmp/case-browser-snap.out 2>&1 \
  || { echo "FAIL: CDP snapshot 失败"; cat /tmp/case-browser-snap.out 2>/dev/null || true; exit 1; }
$K8S_EXEC agent-browser --cdp "$CDP" close >/dev/null 2>&1 || true
echo "CASE OK: case-browser（sidecar CDP 可达）"
