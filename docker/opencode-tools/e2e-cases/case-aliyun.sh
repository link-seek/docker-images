#!/bin/bash
# CASE-ID: case-aliyun
# CASE-DESC: 阿里云身份只读探针（ecs DescribeInstances PageSize 1，只读不写删）
# CASE-COST: low
# CASE-SUGGEST: auto
# 约定：跑在 $K8S_EXEC 之后（pod 内 ALIBABACLOUD_* 环境认证）；无钥匙（占位未替换）则 SKIP，不红。
set -euo pipefail
[ -n "${K8S_EXEC:-}" ] || { echo "FAIL: K8S_EXEC 为空（fine-test.sh 未导出）"; exit 1; }

AK_V="$($K8S_EXEC printenv ALIBABACLOUD_ACCESS_KEY_ID 2>/dev/null || true)"
if [ -z "$AK_V" ] || [ "${AK_V#__ALI}" != "$AK_V" ]; then
  echo "E2E SKIP: case-aliyun（无阿里云身份，key 缺失或为占位）"
  exit 0
fi
RESP="$(timeout 90 $K8S_EXEC aliyun ecs DescribeInstances --RegionId cn-hangzhou --PageSize 1)"
echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'Instances' in d, d; print('Instances TotalCount:', d.get('TotalCount'))"
echo "E2E PASS: case-aliyun"
