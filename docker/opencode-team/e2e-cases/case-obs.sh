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
# AK/SK 为 base64 系字符集，单引号包裹安全；runner 侧展开（细测 runner 为一次性节点）。
PUT="obsutil -e=$ENDPOINT -i=$OBS_TEST_AK -k=$OBS_TEST_SK"
cleanup() { $K8S_EXEC sh -c "$PUT rm obs://$BUCKET/$KEY 2>/dev/null || true" >/dev/null 2>&1 || true; }
trap cleanup EXIT
$K8S_EXEC sh -c "echo e2e-probe-$TAG > /tmp/obs-probe.txt && $PUT cp /tmp/obs-probe.txt obs://$BUCKET/$KEY && rm -f /tmp/obs-probe.txt" \
  || { echo "FAIL: OBS 上传失败"; exit 1; }
echo "UPLOAD OK"
$K8S_EXEC sh -c "$PUT ls obs://$BUCKET/e2e-team/$TAG/" | grep -q "probe.txt" \
  || { echo "FAIL: OBS 上传后 ls 不见 probe.txt"; exit 1; }
echo "VISIBLE OK"
$K8S_EXEC sh -c "$PUT rm obs://$BUCKET/$KEY" \
  || { echo "FAIL: OBS 删除失败"; exit 1; }
echo "DELETE OK"
trap - EXIT
echo "CASE OK: case-obs（上传→可见→删除闭环）"
