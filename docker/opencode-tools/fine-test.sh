#!/bin/bash
# docker/opencode-tools/fine-test.sh — tools 产品细测（商家实现，骨架按固定约定调用）。
# 调用约定（bake-stack.yml 写死）：env 传 DIGEST / API_KEY / SWR_USER / SWR_PASS / TEMP_TAG / E2E_CASES
# + K8S_NS / K8S_DEPLOY / K8S_CONTAINER（k3d+Flux 新预检，#505）；exit 0 + 打印 PASS 行即过，非零即红。
#
# 新预检：同货验证。骨架已在 k3d 里用 Flux 对完账（digest 经 images 注入），本 hook 只做：
#   1) identity：跑的必须是刚打出来的 digest（kubectl 读 deploy image）。
#   2) E2E：select-cases.sh 选单（默认 full；E2E_CASES 可 skip/名单强制），逐个跑 e2e-cases/case-*.sh。
#      用例全部 kubectl exec 打 $K8S_DEPLOY；smoke 为内置，不需要文件。
set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASES_DIR="$HOOK_DIR/e2e-cases"

[ -n "${K8S_DEPLOY:-}" ] || { echo "FAIL: K8S_DEPLOY 为空（骨架 k8s_app 未传）"; exit 1; }
[ -n "${DIGEST:-}" ] || { echo "FAIL: DIGEST 为空（temp 推送未出 digest）"; exit 1; }
K8S_NS="${K8S_NS:-opencode}"
K8S_CONTAINER="${K8S_CONTAINER:-$K8S_DEPLOY}"
export K8S_NS K8S_DEPLOY K8S_CONTAINER
export K8S_EXEC="kubectl exec -n $K8S_NS deploy/$K8S_DEPLOY -c $K8S_CONTAINER --"

identity() { # 货对单：跑的必须是刚打出来的 digest
  local img
  img="$(kubectl -n "$K8S_NS" get "deploy/$K8S_DEPLOY" -o jsonpath='{.spec.template.spec.containers[0].image}')"
  [ -n "$img" ] || { echo "FAIL: deploy/$K8S_DEPLOY 读不到 image"; exit 1; }
  case "$img" in
    *"@${DIGEST}") echo "IDENTITY OK: deploy/$K8S_DEPLOY == $DIGEST" ;;
    *) echo "FAIL: deploy 跑的是 $img，不是刚打出来的 $DIGEST"; exit 1 ;;
  esac
}

identity

# --- E2E 选单 + 逐个跑 ---
CASES="$(E2E_CASES="${E2E_CASES:-}" bash "$CASES_DIR/select-cases.sh")"
echo "E2E cases: ${CASES:-<none>}"

smoke() { # 内置兜底：版本 + skill 文件存在（快、无网、无模型）
  $K8S_EXEC opencode --version
  $K8S_EXEC test -f /root/.agents/skills/open-design/SKILL.md
  echo "E2E PASS: smoke"
}

if [ -z "$CASES" ]; then
  echo "E2E SKIP: 选单为空（E2E_CASES=skip）"
else
  for c in $CASES; do
    if [ "$c" = "smoke" ]; then
      smoke
    else
      [ -f "$CASES_DIR/$c.sh" ] || { echo "FAIL: 用例文件缺失 $CASES_DIR/$c.sh（选单与文件不一致）"; exit 1; }
      bash "$CASES_DIR/$c.sh"
      echo "E2E PASS: $c"
    fi
  done
fi

echo "FINE PASS: tools 细测通过（k3d+Flux 同货，E2E cases: ${CASES:-<none>}）"
