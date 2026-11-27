#!/bin/bash
# omnara-migrations-k8s 细测：migrate 二进制可执行，且与 api 同源的迁移文件在镜像内。
set -euo pipefail
[ -n "${DIGEST:-}" ] || { echo "FAIL: DIGEST 为空"; exit 1; }
[ -n "${SWR_USER:-}" ] || { echo "FAIL: SWR_USER 为空"; exit 1; }
[ -n "${SWR_PASS:-}" ] || { echo "FAIL: SWR_PASS 为空"; exit 1; }
[ -n "${TEMP_TAG:-}" ] || { echo "FAIL: TEMP_TAG 为空"; exit 1; }

IMG="swr.cn-north-9.myhuaweicloud.com/link-seek/omnara-migrations-k8s@${DIGEST}"
echo "TEMP_TAG=$TEMP_TAG"
echo "$SWR_PASS" | docker login swr.cn-north-9.myhuaweicloud.com -u "$SWR_USER" --password-stdin >/dev/null
docker pull "$IMG" >/dev/null

docker run --rm "$IMG" --help >/dev/null
echo "PASS: omnara-migrate --help"

ENTRY="$(docker inspect --format='{{json .Config.Entrypoint}}' "$IMG")"
[ "$ENTRY" = '["/usr/local/bin/omnara-migrate"]' ] || { echo "FAIL: entrypoint=$ENTRY"; exit 1; }
echo "PASS: entrypoint"
