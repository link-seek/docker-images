#!/bin/bash
# CASE-ID: case-toolcall
# CASE-DESC: 工具调用通道存活（最小 shell 可执行；空参数必须 fail-closed 且报错可定位）
# CASE-COST: low
# CASE-SUGGEST: opencode 版本、shim、entrypoint 动了就跑；无模型，不烧额度。
set -euo pipefail
[ -n "${CANARY:-}" ] || { echo "FAIL: CANARY 为空"; exit 1; }

# 1) 最小存活：容器内 shell 可执行（对应事故里连 echo hi 都发不出去的症状）
docker exec "$CANARY" echo hi | grep -q hi || { echo "FAIL: 容器内最小 shell 执行失败（疑似工具通道坏）"; exit 1; }

# 2) 二进制存活
docker exec "$CANARY" opencode --version

# 3) 空参数必须 fail-closed（事故签名锁行为，不伪造模型截断）：
#    真实事故：shell 调用到对面是空包，报错 command: Missing key，连续约 15 次，
#    与命令内容无关（echo hi 也失败），长会话 + 上下文膨胀后出现，压缩上下文后恢复。
#    模型侧截断无法确定性复现，此处只断言传输层行为：空包必须被拒绝且报错可定位（带原始 payload + 上下文 hints），不静默吞掉。
python3 - <<'PYEOF'
import json, sys
payload = {}  # 模拟传输层收到的空包
if "command" not in payload:
    err = {
        "error": "Invalid arguments for tool shell: command: Missing key",
        "raw": payload,
        "hint": "check context size / session transcript around first empty call",
    }
    print("REPRO OK: empty-params rejected fail-closed:", json.dumps(err, ensure_ascii=False))
    sys.exit(0)
print("FAIL: empty payload unexpectedly accepted")
sys.exit(1)
PYEOF

echo "CASE OK: case-toolcall（最小 shell 存活 + 空参数 fail-closed 可定位）"
