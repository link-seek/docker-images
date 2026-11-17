#!/bin/bash
# CASE-ID: case-render
# CASE-DESC: sidecar 经 CDP 出图（中文页截图非空，无模型）
# CASE-COST: low
# CASE-SUGGEST: sidecar/CDP 链动了就跑；出图断言。
set -euo pipefail
[ -n "${K8S_EXEC:-}" ] || { echo "FAIL: K8S_EXEC 为空（fine-test.sh 未导出）"; exit 1; }
CDP="$($K8S_EXEC printenv BROWSER_CDP_URL 2>/dev/null || true)"
[ -n "$CDP" ] || { echo "FAIL: 容器内 BROWSER_CDP_URL 为空（部署侧没给 sidecar 地址）"; exit 1; }
$K8S_EXEC agent-browser --cdp "$CDP" open "data:text/html,<h1>中文测试</h1>" >/dev/null 2>&1 \
  || { echo "FAIL: CDP open 数据页失败"; exit 1; }
$K8S_EXEC agent-browser --cdp "$CDP" screenshot /tmp/case-render.png >/dev/null 2>&1 \
  || { echo "FAIL: CDP screenshot 失败"; exit 1; }
$K8S_EXEC test -s /tmp/case-render.png \
  || { echo "FAIL: 截图为空（sidecar 渲染异常？）"; exit 1; }
$K8S_EXEC agent-browser --cdp "$CDP" close >/dev/null 2>&1 || true
echo "CASE OK: case-render（CDP 出图非空）"
