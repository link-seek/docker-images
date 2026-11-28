#!/bin/bash
# docker/opencode-ops/fine-test.sh —— 本地记忆引擎 e2e（bake-stack 细测 hook）
#
# 调用约定（bake-stack.yml 固定）：env 传 DIGEST/TEMP_TAG/SWR_USER/SWR_PASS 等；
# exit 0 + 打印 PASS 面即过，非零即红。
#
# 测什么（不依赖网络/模型网关）：
#   1) 新卷：写一条带随机暗号的记忆，并搜索到（捕获 + 本地向量检索）
#   2) 再开一个新容器、同卷：还能搜索到（持久化）
# embedding 模型已烘进镜像 /opt/opencode-mem/.cache，测试时 seed 到卷，--network none 保证离线。
set -euo pipefail

REG="swr.cn-north-9.myhuaweicloud.com/link-seek"
VOL="$(mktemp -d /tmp/ops-mem-e2e.XXXXXX)"
trap 'rm -rf "$VOL" || true' EXIT

IMG="$(docker images --format '{{.Repository}}:{{.Tag}}' --filter "reference=${REG}/opencode-ops:*" | grep -v '<none>' | head -1 || true)"
[ -n "$IMG" ] || { echo "FAIL: 本地找不到 ${REG}/opencode-ops:*（构建镜像）"; exit 1; }
echo "IMAGE: $IMG"

CODE="ORANGE-${RANDOM}-${RANDOM}"

run_mode() { # $1 = add|search
  docker run --rm --network none \
    -e CODE="$CODE" -e MODE="$1" \
    -v "$VOL":/root/.local/share/opencode \
    --entrypoint sh "$IMG" -c '
      set -e
      # 镜像烘焙的 embedding 模型 seed 到卷（等价 entrypoint 首次运行）
      if [ -d /opt/opencode-mem/.cache ] && [ ! -d /root/.local/share/opencode/opencode-mem/.cache ]; then
        mkdir -p /root/.local/share/opencode/opencode-mem
        cp -a /opt/opencode-mem/.cache /root/.local/share/opencode/opencode-mem/.cache
      fi
      D="$(ls -d /root/.cache/opencode/npm/opencode-mem@*/*/node_modules/opencode-mem | head -1)"
      cat > /tmp/memtest.mjs <<EOF
import { initConfig } from "$D/dist/config.js"
import { handleAddMemory, handleSearch } from "$D/dist/services/api-handlers.js"
initConfig("/workspace")
if (process.env.MODE === "add") {
  const a = await handleAddMemory({ content: "e2e codeword " + process.env.CODE, containerTag: "opencode-ops", type: "fact", tags: ["e2e"] })
  if (!a.success) { console.error("ADD-FAIL", JSON.stringify(a)); process.exit(1) }
}
const s = await handleSearch(process.env.CODE, undefined, 1, 10)
if (!JSON.stringify(s).includes(process.env.CODE)) { console.error("SEARCH-FAIL", JSON.stringify(s).slice(0, 800)); process.exit(1) }
console.log("MEM-OK", process.env.MODE)
EOF
      node /tmp/memtest.mjs
    '
}

echo "== 1) add + search（新容器/新卷） =="
run_mode add
echo "== 2) 再开一个新容器（同卷）search =="
run_mode search
echo "PASS: opencode-mem e2e (add -> search -> new container -> search)"
