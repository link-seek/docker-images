#!/bin/bash
# docker/litellm-gateway/fine-test.sh — 网关产品细测（商家实现，骨架按固定约定调用）。
# 调用约定（bake-stack.yml 写死）：env 传 DIGEST / API_KEY / SWR_USER / SWR_PASS / STACK_DIR / CANARY；
# exit 0 + 打印 PASS 行即过。canary 由 infra preflight 起在本机 docker（不映射宿主端口）。
set -euo pipefail
# 固定函数契约：实现随镜像同 digest（从 $DIGEST 现场 extract），部署盲调读 verdict；
# 网关断言细节住镜像里，本线不感知。
probe() { # $1=level（实现从被测 canary 本体现场取：零 pull，测的是运行中的字节；rotation 后重取）
  rm -rf /tmp/hc && mkdir -p /tmp/hc
  docker cp "$CANARY:/app/healthcheck" /tmp/hc/ && docker cp "$CANARY:/app/models-denied.json" /tmp/hc/ && chmod +x /tmp/hc/healthcheck
  ENDPOINT="http://$(docker inspect "$CANARY" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'):4000"
  sudo /tmp/hc/healthcheck --base-url "$ENDPOINT" --api-key "$API_KEY" --level "$1" --container "$CANARY"
}
probe full
echo "DETAIL OK: 细测通过"
# 轮换重测：重起 canary（新随机 master），轻链路语义必须不变（master 随便换不影响透传）
# canary-run.sh 仍由 core 每次部署 scp 到目标机 /tmp/（lifecycle 脚本，与探针解耦）
sudo -E REMOTE_DIR=/root/stacks/litellm-gateway CANDIDATE_DIGEST="$DIGEST" \
  SWR_USER="$SWR_USER" SWR_PASS="$SWR_PASS" \
  bash "/tmp/canary-run.sh"
probe boot
echo "ROTATE OK: master 轮换不影响透传"
