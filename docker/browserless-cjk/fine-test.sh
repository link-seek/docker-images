#!/bin/bash
# docker/browserless-cjk/fine-test.sh — browserless-chrome-cjk 运行时细测（商家实现，骨架按固定约定调用）。
# 调用约定（bake-stack.yml 写死）：env 传 DIGEST / TEMP_TAG（+ GHCR_IMAGE 由骨架 job env 透传，
# runner 已被骨架 docker login 过 GHCR）；exit 0 + 打印 PASS 行即过，非零即红。
#
# ghcr_temp_only=true：temp 只在 GHCR（SWR 只留正式版），本 hook 从 GHCR 拉 temp 测。
# 测三件事（跑的即刚打出来的 digest，DIGEST 货对单保证）：
#   1) 中文字体在位（fc-list 有 noto cjk）——本镜像存在的唯一理由；
#   2) /pressure 200（TOKEN 鉴权通）；
#   3) 中文页截图非空（POST /chromium/screenshot，渲染链路通）。
set -euo pipefail

[ -n "${DIGEST:-}" ] || { echo "FAIL: DIGEST 为空（temp 推送未出 digest）"; exit 1; }
[ -n "${TEMP_TAG:-}" ] || { echo "FAIL: TEMP_TAG 为空"; exit 1; }
: "${GHCR_IMAGE:?FAIL: GHCR_IMAGE 为空（骨架 job env 未透传）}"
TOKEN="ci-fine-test-token"
CONTAINER="fine-browserless-$$"

docker pull "$GHCR_IMAGE:$TEMP_TAG"

cleanup() { docker rm -f "$CONTAINER" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run -d --name "$CONTAINER" --shm-size=2g -e TOKEN="$TOKEN" "$GHCR_IMAGE:$TEMP_TAG"

echo "等待 /pressure（最多 120s）..."
for i in $(seq 1 24); do
  if docker exec "$CONTAINER" curl -fsS "http://127.0.0.1:3000/pressure?token=$TOKEN" | grep -q pressure; then
    echo "PRESSURE OK"
    break
  fi
  [ "$i" = "24" ] && { echo "FAIL: /pressure 120s 未就绪"; docker logs "$CONTAINER" | tail -20; exit 1; }
  sleep 5
done

docker exec "$CONTAINER" sh -c "fc-list | grep -ci 'noto.*cjk'" | grep -qE '^[1-9]' \
  && echo "CJK FONTS OK" || { echo "FAIL: 中文字体缺失"; exit 1; }

docker exec "$CONTAINER" curl -fsS -X POST "http://127.0.0.1:3000/chromium/screenshot?token=$TOKEN" \
  -H 'Content-Type: application/json' -d '{"url": "https://example.com"}' \
  -o /tmp/fine-shot.png
SIZE="$(docker exec "$CONTAINER" stat -c%s /tmp/fine-shot.png)"
[ "$SIZE" -gt 10240 ] && echo "SCREENSHOT OK: ${SIZE} bytes" || { echo "FAIL: 截图过小/失败（${SIZE} bytes）"; exit 1; }

echo "FINE PASS: browserless-chrome-cjk 细测通过（pressure + CJK + screenshot）"
