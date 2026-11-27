#!/bin/bash
# omnara-web-k8s 细测：静态资源存在、nginx 配置有效、镜像非 root。
set -euo pipefail
[ -n "${DIGEST:-}" ] || { echo "FAIL: DIGEST 为空"; exit 1; }
[ -n "${SWR_USER:-}" ] || { echo "FAIL: SWR_USER 为空"; exit 1; }
[ -n "${SWR_PASS:-}" ] || { echo "FAIL: SWR_PASS 为空"; exit 1; }
[ -n "${TEMP_TAG:-}" ] || { echo "FAIL: TEMP_TAG 为空"; exit 1; }

IMG="swr.cn-north-9.myhuaweicloud.com/link-seek/omnara-web-k8s@${DIGEST}"
echo "TEMP_TAG=$TEMP_TAG"
echo "$SWR_PASS" | docker login swr.cn-north-9.myhuaweicloud.com -u "$SWR_USER" --password-stdin >/dev/null
docker pull "$IMG" >/dev/null

docker run --rm --entrypoint /bin/sh "$IMG" -c '
  test -f /usr/share/nginx/omnara/index.html
  test -d /usr/share/nginx/omnara/assets
  nginx -t
' >/dev/null
echo "PASS: web assets + nginx config"

USER_ID="$(docker inspect --format='{{.Config.User}}' "$IMG")"
[ "$USER_ID" = "101" ] || { echo "FAIL: expected user 101, got ${USER_ID:-<empty>}"; exit 1; }
echo "PASS: non-root user"
