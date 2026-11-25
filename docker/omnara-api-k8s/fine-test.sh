#!/bin/bash
# docker/omnara-api-k8s/fine-test.sh — 静态自检（不启动容器：api 无库起不来）。
# 调用约定（bake-stack.yml 写死）：env 传 DIGEST / SWR_USER / SWR_PASS / TAG；
# exit 0 + 打印 PASS 行即过，非零即红。
# 验：digest 可拉；Entrypoint 是 api 二进制；关键 ENV 在位；非 root 用户；amd64；
# 从镜像里 cp 出 mcp-registry.json 并校验 JSON 合法。
set -euo pipefail

[ -n "${DIGEST:-}" ] || { echo "FAIL: DIGEST 为空"; exit 1; }
[ -n "${SWR_USER:-}" ] || { echo "FAIL: SWR_USER 为空"; exit 1; }
[ -n "${SWR_PASS:-}" ] || { echo "FAIL: SWR_PASS 为空"; exit 1; }
[ -n "${TEMP_TAG:-}" ] || { echo "FAIL: TEMP_TAG 为空"; exit 1; }

IMG="swr.cn-north-9.myhuaweicloud.com/link-seek/omnara-api-k8s@${DIGEST}"
echo "TEMP_TAG=$TEMP_TAG"
echo "$SWR_PASS" | docker login swr.cn-north-9.myhuaweicloud.com -u "$SWR_USER" --password-stdin >/dev/null
docker pull "$IMG" >/dev/null

ENTRY="$(docker inspect --format='{{json .Config.Entrypoint}}' "$IMG")"
[ "$ENTRY" = '["/usr/local/bin/omnara-api"]' ] || { echo "FAIL: entrypoint=$ENTRY"; exit 1; }
echo "ENTRYPOINT OK: $ENTRY"

ENVIRON="$(docker inspect --format='{{json .Config.Env}}' "$IMG")"
case "$ENVIRON" in
  *OMNARA_WEB_SERVING=disabled*OMNARA_MCP_REGISTRY_SNAPSHOT_PATH=/app/mcp-registry/mcp-registry.json*) ;;
  *) echo "FAIL: env 缺关键项: $ENVIRON"; exit 1 ;;
esac
echo "ENV OK"

USER="$(docker inspect --format='{{.Config.User}}' "$IMG")"
ARCH="$(docker inspect --format='{{.Architecture}}' "$IMG")"
[ "$ARCH" = "amd64" ] || { echo "FAIL: arch=$ARCH"; exit 1; }
case "$USER" in *nonroot*|*65532*) ;; *) echo "FAIL: user=$USER"; exit 1 ;; esac
echo "USER/ARCH OK: $USER $ARCH"

CID="$(docker create "$IMG")"
trap 'docker rm "$CID" >/dev/null' EXIT
docker cp "$CID:/app/mcp-registry/mcp-registry.json" /tmp/omnara-mcp-registry.json >/dev/null
python3 -c "import json; d=json.load(open('/tmp/omnara-mcp-registry.json')); servers=d.get('servers', d); assert isinstance(d, dict) and isinstance(servers, dict) and len(servers) > 1000, len(servers) if isinstance(servers, dict) else type(servers); print('MCP-REGISTRY OK: servers', len(servers))"
rm -f /tmp/omnara-mcp-registry.json

echo "PASS: omnara-api-k8s $DIGEST 静态自检通过（entrypoint/env/user/arch/mcp-registry）"
