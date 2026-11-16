#!/bin/bash
# docker/litellm-gateway/fine-test.sh — 网关产品细测（商家实现，骨架按固定约定调用）。
# 调用约定（bake-stack.yml 写死）：env 传 DIGEST / API_KEY / SWR_USER / SWR_PASS / TEMP_TAG / E2E_CASES
# + K8S_NS / K8S_DEPLOY / K8S_CONTAINER（k3d+Flux 新预检）；exit 0 + 打印 PASS 行即过，非零即红。
#
# 新预检：同货验证。骨架已在 k3d 里用 Flux 对完账（digest 经 images 注入，
# command 已覆盖为直跑 litellm、entrypoint/tailscale 全跳过），本 hook 只做：
#   1) identity：跑的必须是刚打出来的 digest（kubectl 读 deploy image）。
#   2) E2E：port-forward svc → /v1/models（key 从预检 secret 实取，鉴权自洽；只读模型列表，不调上游）。
set -euo pipefail

NS="${K8S_NS:-litellm}"
DEPLOY="${K8S_DEPLOY:-litellm-gateway}"
[ -n "${DIGEST:-}" ] || { echo "FAIL: DIGEST 为空（temp 推送未出 digest）"; exit 1; }

identity() { # 货对单：跑的必须是刚打出来的 digest
  local img
  img="$(kubectl -n "$NS" get "deploy/$DEPLOY" -o jsonpath='{.spec.template.spec.containers[0].image}')"
  [ -n "$img" ] || { echo "FAIL: deploy/$DEPLOY 读不到 image"; exit 1; }
  case "$img" in
    *"@${DIGEST}") echo "IDENTITY OK: deploy/$DEPLOY == $DIGEST" ;;
    *) echo "FAIL: deploy 跑的是 $img，不是刚打出来的 $DIGEST"; exit 1 ;;
  esac
}

identity

if [ "${E2E_CASES:-}" = "skip" ]; then
  echo "E2E SKIP: E2E_CASES=skip"
  echo "FINE PASS: 网关细测通过（k3d+Flux 同货，identity；E2E cases: skip）"
  exit 0
fi

# --- E2E：模型列表（port-forward 直打 svc，不出 k3d）---
kubectl -n "$NS" rollout status "deploy/$DEPLOY" --timeout=180s >/dev/null
kubectl -n "$NS" port-forward "svc/litellm-gateway" 14000:4000 >/tmp/pf.log 2>&1 &
PF_PID=$!
trap 'kill $PF_PID 2>/dev/null || true' EXIT
for i in $(seq 1 30); do
  curl -sf -o /dev/null http://127.0.0.1:14000/v1/models && break
  [ "$i" = "30" ] && { echo "FAIL: port-forward 后 /v1/models 30 次不通"; cat /tmp/pf.log; exit 1; }
  sleep 5
done
MASTER_KEY="$(kubectl -n "$NS" get secret litellm-env -o jsonpath='{.data.LITELLM_MASTER_KEY}' | base64 -d)"
[ -n "$MASTER_KEY" ] || { echo "FAIL: secret litellm-env 无 LITELLM_MASTER_KEY"; exit 1; }
RESP="$(curl -sf -H "Authorization: Bearer $MASTER_KEY" http://127.0.0.1:14000/v1/models)"
echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); assert isinstance(d.get('data'),list) and len(d['data'])>0, 'empty model list'; print('models:', len(d['data']))"
echo "E2E PASS: models-list"
kill $PF_PID 2>/dev/null || true
trap - EXIT
echo "FINE PASS: 网关细测通过（k3d+Flux 同货，identity + models-list）"
