#!/bin/bash
# docker/opencode-ops/fine-test.sh —— 本地记忆功能真测（bake-stack 细测 hook）
#
# 调用约定（bake-stack.yml 固定）：env 传 DIGEST/TEMP_TAG/SWR_USER/SWR_PASS 等；
# exit 0 + 打印 PASS 行即过，非零即红。
#
# 测什么（不依赖模型网关，走 opencode-mem 自带的本地 web API）：
#   1) 写入一条带随机暗号的记忆
#   2) 列表 / 搜索都能查到（捕获 + 本地向量检索）
#   3) 删容器、同卷重开 → 还能查到（持久化）
set -euo pipefail

REG="swr.cn-north-9.myhuaweicloud.com/link-seek"
NAME="ops-mem-e2e-$$"
VOL="$(mktemp -d /tmp/ops-mem-e2e.XXXXXX)"
cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; rm -rf "$VOL"; }
trap cleanup EXIT

IMG="$(docker images --format '{{.Repository}}:{{.Tag}}' --filter "reference=${REG}/opencode-ops:*" | grep -v '<none>' | head -1 || true)"
[ -n "$IMG" ] || { echo "FAIL: 本地找不到 ${REG}/opencode-ops:*（构建镜像）"; exit 1; }
echo "IMAGE: $IMG"

start() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  docker run -d --name "$NAME" --network host \
    -e OPENCODE_SERVER_PASSWORD=e2e-dummy \
    -e LITELLM_BASE_URL=http://127.0.0.1:1 \
    -e LITELLM_API_KEY=e2e-dummy \
    -v "$VOL":/root/.local/share/opencode \
    "$IMG" serve --port 4097 --hostname 127.0.0.1 >/dev/null
  local i
  for i in $(seq 1 90); do
    if docker exec "$NAME" sh -c 'curl -sf -o /dev/null http://127.0.0.1:4747/api/health' >/dev/null 2>&1; then
      echo "memory web ready (${i}x2s)"; return 0
    fi
    sleep 2
  done
  echo "FAIL: memory web server 未就绪"
  docker logs "$NAME" 2>&1 | tail -50
  return 1
}

CODE="ORANGE-${RANDOM}-${RANDOM}"
start

echo "== 1) 写入记忆 =="
docker exec "$NAME" sh -c "curl -sS -m 900 -X POST -H 'Content-Type: application/json' \
  -d '{\"content\":\"e2e memory codeword ${CODE}\",\"containerTag\":\"opencode-ops\",\"type\":\"fact\",\"tags\":[\"e2e\"]}' \
  http://127.0.0.1:4747/api/memories" > /tmp/ops-mem-write.json || true
head -c 300 /tmp/ops-mem-write.json; echo

echo "== 2) 列表 + 搜索（同一容器） =="
docker exec "$NAME" sh -c "curl -sS -m 120 'http://127.0.0.1:4747/api/memories?page=1&pageSize=100'" > /tmp/ops-mem-list1.json
grep -q "$CODE" /tmp/ops-mem-list1.json || { echo "FAIL: 写入后列表里没有该记忆"; head -c 800 /tmp/ops-mem-list1.json; exit 1; }
docker exec "$NAME" sh -c "curl -sS -m 120 'http://127.0.0.1:4747/api/search?q=${CODE}'" > /tmp/ops-mem-search1.json
grep -q "$CODE" /tmp/ops-mem-search1.json || { echo "FAIL: 写入后搜索不到"; head -c 800 /tmp/ops-mem-search1.json; exit 1; }

echo "== 3) 重启容器（同卷）后再查 =="
start
docker exec "$NAME" sh -c "curl -sS -m 120 'http://127.0.0.1:4747/api/memories?page=1&pageSize=100'" > /tmp/ops-mem-list2.json
grep -q "$CODE" /tmp/ops-mem-list2.json || { echo "FAIL: 重启后列表里记忆丢失"; head -c 800 /tmp/ops-mem-list2.json; exit 1; }
docker exec "$NAME" sh -c "curl -sS -m 120 'http://127.0.0.1:4747/api/search?q=${CODE}'" > /tmp/ops-mem-search2.json
grep -q "$CODE" /tmp/ops-mem-search2.json || { echo "FAIL: 重启后搜索不到"; head -c 800 /tmp/ops-mem-search2.json; exit 1; }

echo "PASS: opencode-mem e2e (write -> list/search -> restart -> list/search)"
