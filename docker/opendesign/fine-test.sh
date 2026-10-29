#!/bin/bash
# docker/opendesign/fine-test.sh — OD 产品细测 hook（商家实现，骨架按固定约定调用）。
# 调用约定（bake-stack.yml 写死）：env 传 DIGEST / API_KEY / SWR_USER / SWR_PASS / STACK_DIR / CANARY / TEMP_TAG；
# exit 0 + 打印 PASS 行即过，非零即红（红不转正式 tag）。
#
# 行为等价旧 bake-od 的放行门：
#   1) SWR 候选 pin 精确可拉取（缺 SWR 凭证则跳过，沿用旧逻辑）
#   2) 原样跑 docker/opendesign/e2e.sh（GHCR 同版存活 + litellm 免费档 byok + 对话三件套）
set -euo pipefail

: "${DIGEST:?DIGEST required（骨架传刚构建的 temp digest）}"
: "${API_KEY:?API_KEY required（免费档 byok 真 key）}"
: "${TEMP_TAG:?TEMP_TAG required（骨架传 ci-<run号>）}"
: "${GHCR_IMAGE:?GHCR_IMAGE required（骨架 job env）}"
: "${SWR_IMAGE:?SWR_IMAGE required（骨架 job env）}"

E2E_IMAGE="${GHCR_IMAGE}:${TEMP_TAG}"

echo "===== 1/2 SWR 候选 pin 可拉取（$SWR_IMAGE:$TEMP_TAG） ====="
if [ -n "${SWR_USER:-}" ] && [ -n "${SWR_PASS:-}" ]; then
  SWR_REGISTRY="$(echo "$SWR_IMAGE" | cut -d/ -f1)"
  echo "$SWR_PASS" | docker login "$SWR_REGISTRY" -u "$SWR_USER" --password-stdin
  CANDIDATE="${SWR_IMAGE}:${TEMP_TAG}"
  docker pull -q "$CANDIDATE"
  GOT="$(docker image inspect "$CANDIDATE" --format '{{index .RepoDigests 0}}' | sed 's/.*@//')"
  if [ "$GOT" != "$DIGEST" ]; then
    echo "FAIL: SWR 候选 digest=$GOT，与刚构建的 $DIGEST 不一致"
    exit 1
  fi
  echo "SWR PIN OK: $CANDIDATE == $DIGEST"
else
  echo "SKIP: SWR 凭证未配；GHCR 存活由 e2e 验，SWR 侧 pin 可拉取性留待凭证补齐"
fi

echo "===== 2/2 产品 e2e（GHCR 同版 $E2E_IMAGE；红不转正式 tag） ====="
export E2E_IMAGE
export CANDIDATE_DIGEST="$DIGEST"
export GO_BACKEND_KEY="$API_KEY"
export LITELLM_IMAGE="${LITELLM_IMAGE:-ghcr.io/link-seek/litellm-gateway:latest}"
bash docker/opendesign/e2e.sh

echo "PASS: OD 细测通过（SWR pin + 产品 e2e）"
