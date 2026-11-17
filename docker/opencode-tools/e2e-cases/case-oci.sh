#!/bin/bash
# CASE-ID: case-oci
# CASE-DESC: OCI 身份只读探针（availability-domain list，不写不删）
# CASE-COST: low
# CASE-SUGGEST: auto
# 约定：跑在 $K8S_EXEC 之后（pod 内 OCI_CLI_* 环境认证）；无钥匙（占位未替换）则 SKIP，不红。
set -euo pipefail
[ -n "${K8S_EXEC:-}" ] || { echo "FAIL: K8S_EXEC 为空（fine-test.sh 未导出）"; exit 1; }

USER_V="$($K8S_EXEC printenv OCI_CLI_USER 2>/dev/null || true)"
if [ -z "$USER_V" ] || [ "${USER_V#__OCI}" != "$USER_V" ]; then
  echo "E2E SKIP: case-oci（无 OCI 身份，OCI_CLI_USER 缺失或为占位）"
  exit 0
fi
TENANCY="$($K8S_EXEC printenv OCI_CLI_TENANCY)"
RESP="$(timeout 90 $K8S_EXEC oci iam availability-domain list --compartment-id "$TENANCY" --output json)"
echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); assert isinstance(d.get('data'),list) and len(d['data'])>0, 'empty AD list'; print('ADs:', [a['name'] for a in d['data']])"
echo "E2E PASS: case-oci"
