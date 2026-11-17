#!/bin/bash
# docker/opencode-team/fine-test.sh — team 运行时细测（商家实现，骨架按固定约定调用）。
# 调用约定（bake-stack.yml 写死）：env 传 DIGEST / API_KEY / SWR_USER / SWR_PASS / TEMP_TAG / E2E_CASES
# + K8S_NS / K8S_DEPLOY / K8S_CONTAINER（k3d+Flux 新预检，#505）；exit 0 + 打印 PASS 行即过，非零即红。
#
# 新预检：同货验证。骨架已在 k3d 里用 Flux 对完账（team digest 经 images 注入，
# browserless 取 manifest tag——bootstrap 要求先转正 browserless），本 hook 只做：
#   1) identity：k3d 里跑的必须是刚打出来的 digest（kubectl 读 deploy image）。
#   2) 链路：pod 内 agent-browser connect 到同 ns browserless Service（CDP over ws + token 鉴权）
#      → open → snapshot 断言 → screenshot → close。
# TOKEN 用 preflight-env.conf 里写死的 dummy-preflight（模板进仓，同 Secret 两边同值）。
set -euo pipefail

[ -n "${K8S_DEPLOY:-}" ] || { echo "FAIL: K8S_DEPLOY 为空（骨架 k8s_app 未传）"; exit 1; }
[ -n "${DIGEST:-}" ] || { echo "FAIL: DIGEST 为空（temp 推送未出 digest）"; exit 1; }
K8S_NS="${K8S_NS:-opencode-team}"
K8S_CONTAINER="${K8S_CONTAINER:-opencode}"
K8S_EXEC="kubectl -n $K8S_NS exec deploy/$K8S_DEPLOY -c $K8S_CONTAINER --"
export K8S_NS K8S_DEPLOY K8S_CONTAINER

TOKEN="dummy-preflight"
WS_URL="ws://browserless:3000/chromium?token=$TOKEN"

identity() { # 货对单：跑的必须是刚打出来的 digest
  local img
  img="$(kubectl -n "$K8S_NS" get "deploy/$K8S_DEPLOY" -o jsonpath='{.spec.template.spec.containers[0].image}')"
  [ -n "$img" ] || { echo "FAIL: deploy/$K8S_DEPLOY 读不到 image"; exit 1; }
  case "$img" in
    *"@${DIGEST}") echo "IDENTITY OK: deploy/$K8S_DEPLOY == $DIGEST" ;;
    *) echo "FAIL: deploy 跑的是 $img，不是刚打出来的 $DIGEST"; exit 1 ;;
  esac
}

smoke() { # 内置兜底：版本 + skill 文件 + MCP 烘焙可用（快、无网、无模型；2026-11-17 脏缓存教训）
  $K8S_EXEC opencode --version
  $K8S_EXEC test -f /root/.agents/skills/open-design/SKILL.md
  $K8S_EXEC command -v open-design-mcp
  $K8S_EXEC timeout 25 open-design-mcp --help | grep -q '\[open-design\]'
  echo "E2E PASS: smoke"
}

link() { # 全链路：agent-browser 经 CDP 连 browserless（example.com 外网，runner/k3d 均可达）
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
  echo "E2E PASS: link（agent-browser CDP→browserless 全链路）"
}

identity
smoke
if [ "${E2E_CASES:-}" = "skip" ]; then
  echo "E2E SKIP: E2E_CASES=skip，只认版本+连通"
else
  link
fi

echo "FINE PASS: opencode-team 细测通过（k3d+Flux 同货，E2E_CASES: ${E2E_CASES:-<full>}）"
