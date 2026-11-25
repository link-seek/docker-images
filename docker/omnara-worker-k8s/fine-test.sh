#!/bin/bash
# fine-test.sh — 静态自检（不启动容器）：entrypoint/env/user/arch + cp 出二进制验存在。
# 调用约定见 bake-stack.yml：env 传 DIGEST/SWR_USER/SWR_PASS/TEMP_TAG。
set -euo pipefail

[ -n "${DIGEST:-}" ] || { echo "FAIL: DIGEST 为空"; exit 1; }
[ -n "${SWR_USER:-}" ] || { echo "FAIL: SWR_USER 为空"; exit 1; }
[ -n "${SWR_PASS:-}" ] || { echo "FAIL: SWR_PASS 为空"; exit 1; }
[ -n "${TEMP_TAG:-}" ] || { echo "FAIL: TEMP_TAG 为空"; exit 1; }

EXPECTED_BIN="${EXPECTED_BIN:-/usr/local/bin/omnara-worker}"
EXPECTED_ENV="${EXPECTED_ENV:-}"
IMG="swr.cn-north-9.myhuaweicloud.com/link-seek/${IMAGE_SLUG:?IMAGE_SLUG 未设置}@${DIGEST}"
echo "TEMP_TAG=$TEMP_TAG"
[ -n "$EXPECTED_BIN" ]
echo "$SWR_PASS" | docker login swr.cn-north-9.myhuaweicloud.com -u "$SWR_USER" --password-stdin >/dev/null
docker pull "$IMG" >/dev/null

ENTRY="$(docker inspect --format='{{json .Config.Entrypoint}}' "$IMG")"
case "$ENTRY" in
  *"$EXPECTED_BIN"*) echo "ENTRYPOINT OK: $ENTRY" ;;
  *) echo "FAIL: entrypoint=$ENTRY, want *$EXPECTED_BIN*"; exit 1 ;;
esac

if [ -n "$EXPECTED_ENV" ]; then
  ENVIRON="$(docker inspect --format='{{json .Config.Env}}' "$IMG")"
  case "$ENVIRON" in
    *"$EXPECTED_ENV"*) echo "ENV OK" ;;
    *) echo "FAIL: env 缺 $EXPECTED_ENV: $ENVIRON"; exit 1 ;;
  esac
fi

USER="$(docker inspect --format='{{.Config.User}}' "$IMG")"
ARCH="$(docker inspect --format='{{.Architecture}}' "$IMG")"
[ "$ARCH" = "amd64" ] || { echo "FAIL: arch=$ARCH"; exit 1; }
case "$USER" in *nonroot*|*65532*) ;; *) echo "FAIL: user=$USER"; exit 1 ;; esac
echo "USER/ARCH OK: $USER $ARCH"

CID="$(docker create "$IMG")"
trap 'docker rm "$CID" >/dev/null' EXIT
docker cp "$CID:$EXPECTED_BIN" /tmp/omnara-probe-bin >/dev/null
[ -s /tmp/omnara-probe-bin ] || { echo "FAIL: 拷不出 $EXPECTED_BIN"; exit 1; }
rm -f /tmp/omnara-probe-bin

echo "PASS: ${IMAGE_SLUG} $DIGEST 静态自检通过（entrypoint/user/arch/bin）"
