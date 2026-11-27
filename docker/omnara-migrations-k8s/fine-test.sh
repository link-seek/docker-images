#!/bin/bash
# omnara-migrations-k8s 细测：migrate 二进制可执行，且入口点正确。
# 该二进制没有 --help；无配置运行会打印 load migrate config 并以 1 退出，用它证明二进制可执行。
set -euo pipefail
[ -n "${DIGEST:-}" ] || { echo "FAIL: DIGEST 为空"; exit 1; }
[ -n "${SWR_USER:-}" ] || { echo "FAIL: SWR_USER 为空"; exit 1; }
[ -n "${SWR_PASS:-}" ] || { echo "FAIL: SWR_PASS 为空"; exit 1; }
[ -n "${TEMP_TAG:-}" ] || { echo "FAIL: TEMP_TAG 为空"; exit 1; }

IMG="swr.cn-north-9.myhuaweicloud.com/link-seek/omnara-migrations-k8s@${DIGEST}"
echo "TEMP_TAG=$TEMP_TAG"
echo "$SWR_PASS" | docker login swr.cn-north-9.myhuaweicloud.com -u "$SWR_USER" --password-stdin >/dev/null
docker pull "$IMG" >/dev/null

ENTRY="$(docker inspect --format='{{json .Config.Entrypoint}}' "$IMG")"
[ "$ENTRY" = '["/usr/local/bin/omnara-migrate"]' ] || { echo "FAIL: entrypoint=$ENTRY"; exit 1; }

OUT="$(docker run --rm "$IMG" 2>&1 || true)"
case "$OUT" in
  *"load migrate config"*) ;;
  *) echo "FAIL: binary did not start: $OUT"; exit 1 ;;
esac
echo "PASS: omnara-migrate binary + entrypoint"
