#!/bin/bash
# docker/opencode-tools/fine-test.sh — tools 产品细测（商家实现，骨架按固定约定调用）。
# 调用约定（bake-stack.yml 写死）：env 传 DIGEST / API_KEY / SWR_USER / SWR_PASS / STACK_DIR / CANARY / TEMP_TAG / E2E_CASES；
# exit 0 + 打印 PASS 行即过，非零即红。
#
# 两段：
#   1) canary 探针（沿用老 bake-tools 行为）：preflight 已把栈装到本机，探针脚本由 infra 现场 scp 到 /tmp/。
#   2) 镜像 E2E：select-cases.sh 选单（默认 auto 走 Jev；E2E_CASES 可 skip/full/名单强制），逐个跑 e2e-cases/case-*.sh。
#      用例全部 docker exec 打 $CANARY（跑的即刚打出的 digest，零 pull）；smoke 为内置，不需要文件。
set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASES_DIR="$HOOK_DIR/e2e-cases"

[ -n "${CANARY:-}" ] || { echo "FAIL: CANARY 为空（骨架 canary_name 未传）"; exit 1; }
[ -n "${DIGEST:-}" ] || { echo "FAIL: DIGEST 为空（temp 推送未出 digest）"; exit 1; }

identity() { # 货对单：跑的必须是刚打出来的 digest
  local ref
  ref="$(docker inspect "$CANARY" --format '{{.Config.Image}}')"
  [ "${ref##*@}" = "$DIGEST" ] || { echo "FAIL: $CANARY 创建自 $ref，不是刚打出来的 $DIGEST"; exit 1; }
  echo "IDENTITY OK: $CANARY == $DIGEST"
}

# --- 1) canary 探针（老行为原样保留） ---
if [ -f /tmp/canary-probe.sh ]; then
  RDIR=/root/stacks/opencode-prod  # 与 infra hw21 manifest 注释一致：宿主机路径保持历史值，不迁移
  sudo -E PROBE_LEVEL=full REMOTE_DIR="$RDIR" CANDIDATE_DIGEST="$DIGEST" bash /tmp/canary-probe.sh
  echo "CANARY OK: 探针通过（drain 在 img 机无网关则脚本自判跳过）"
else
  echo "FAIL: /tmp/canary-probe.sh 缺失（preflight 未落探针脚本，fail-closed）"
  exit 1
fi

identity

# --- 2) E2E 选单 + 逐个跑 ---
export BASE_REF="${BASE_REF:-}" HEAD_REF="${HEAD_REF:-HEAD}"
CASES="$(E2E_CASES="${E2E_CASES:-}" bash "$CASES_DIR/select-cases.sh")"
echo "E2E cases: ${CASES:-<none>}"

smoke() { # 内置兜底：版本 + skill 文件存在（快、无网、无模型）
  docker exec "$CANARY" opencode --version
  docker exec "$CANARY" test -f /root/.agents/skills/open-design/SKILL.md
  echo "E2E PASS: smoke"
}

if [ -z "$CASES" ]; then
  echo "E2E SKIP: 选单为空（E2E_CASES=skip），只认 canary 结论"
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

echo "FINE PASS: tools 细测通过（canary + E2E cases: ${CASES:-<none>}）"
