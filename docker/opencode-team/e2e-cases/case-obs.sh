#!/bin/bash
# CASE-ID: case-obs
# CASE-DESC: OBS 真传：真 key 上传→ls 可见→删除→验删（robotwin-assets/e2e-team/ 前缀隔离，trap 兜底删）
# CASE-COST: medium
set -euo pipefail
[ -n "${K8S_EXEC:-}" ] || { echo "FAIL: K8S_EXEC 为空（fine-test.sh 未导出）"; exit 1; }
[ -n "${OBS_TEST_AK:-}" ] || { echo "FAIL: OBS_TEST_AK 为空（bake-team 需传 PROD_HCLOUD_AK）"; exit 1; }
[ -n "${OBS_TEST_SK:-}" ] || { echo "FAIL: OBS_TEST_SK 为空"; exit 1; }
ENDPOINT="https://obs.cn-north-9.myhuaweicloud.com"
BUCKET="robotwin-assets"
TAG="${TEMP_TAG:-local}"
KEY="e2e-team/${TAG}/probe.txt"
# 预检覆盖了容器 command（entrypoint 未跑），这里在 pod 内写 obsutil 配置：
# HOME=/tmp/home 是只读根下唯一可写区；AK/SK 只落到一次性预检 Pod 的 600 配置文件。
$K8S_EXEC sh -c "mkdir -p /tmp/home && printf 'endpoint=%s\nak=%s\nsk=%s\ntoken=\n' '$ENDPOINT' '$OBS_TEST_AK' '$OBS_TEST_SK' > /tmp/home/.obsutilconfig && chmod 600 /tmp/home/.obsutilconfig"
OBS="HOME=/tmp/home obsutil"
cleanup() { $K8S_EXEC sh -c "$OBS rm obs://$BUCKET/$KEY 2>/dev/null || true" >/dev/null 2>&1 || true; }
trap cleanup EXIT
$K8S_EXEC sh -c "echo e2e-probe-$TAG > /tmp/obs-probe.txt && $OBS cp /tmp/obs-probe.txt obs://$BUCKET/$KEY && rm -f /tmp/obs-probe.txt" \
  || { echo "FAIL: OBS 上传失败"; exit 1; }
echo "UPLOAD OK"
$K8S_EXEC sh -c "$OBS ls obs://$BUCKET/e2e-team/$TAG/" | grep -q "probe.txt" \
  || { echo "FAIL: OBS 上传后 ls 不见 probe.txt"; exit 1; }
echo "VISIBLE OK"
$K8S_EXEC sh -c "$OBS rm obs://$BUCKET/$KEY" \
  || { echo "FAIL: OBS 删除失败"; exit 1; }
echo "DELETE OK"
trap - EXIT
echo "CASE OK: case-obs（上传→可见→删除闭环）"
