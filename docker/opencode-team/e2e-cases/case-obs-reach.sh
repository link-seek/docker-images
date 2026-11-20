#!/bin/bash
# CASE-ID: case-obs-reach
# CASE-DESC: OBS 端点可达（dummy key 打 ls：403/400/NoSuchBucket 均算通；只验链路不验权，不耗 key）
# CASE-COST: low
set -euo pipefail
[ -n "${K8S_EXEC:-}" ] || { echo "FAIL: K8S_EXEC 为空（fine-test.sh 未导出）"; exit 1; }
# 预检覆盖了容器 command（entrypoint 没跑），配置在这里现写；env 来自 Secret。
# 只读根：/root 为可写 emptyDir，obsutil 配置写 /root/.obsutilconfig。
$K8S_EXEC sh -c 'mkdir -p /root; AK="${HCLOUD_AK:-${OBS_AK:-}}"; SK="${HCLOUD_SK:-${OBS_SK:-}}"; if [ -n "$AK" ]; then printf "endpoint=%s\nak=%s\nsk=%s\ntoken=\n" "$OBS_ENDPOINT" "$AK" "$SK"  > /root/.obsutilconfig; fi; echo config-ok' > /dev/null
OUT=$($K8S_EXEC sh -c 'obsutil ls obs://dummy-probe-$$ 2>&1' || true)
echo "$OUT" | head -n 5
echo "$OUT" | grep -aqE "403|400|NoSuchBucket|InvalidAccessKey|AccessDenied" && echo "OBS REACHABLE" || { echo "FAIL: OBS endpoint unreachable"; exit 1; }
echo "CASE OK: case-obs-reach"
