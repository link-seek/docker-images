#!/bin/bash
# CASE-ID: case-cloudrobo
# CASE-DESC: CloudRobo 控制面 CLI 冒烟（--help/--version/SDK import 离线可跑；有 AK 才跑 workspace list 只读探针）
# CASE-COST: low
# CASE-SUGGEST: auto
# 约定：跑在 $K8S_EXEC 之后；无 HUAWEI_CLOUD_AK 则只跑离线冒烟，live 探针 SKIP，不红。
set -euo pipefail
[ -n "${K8S_EXEC:-}" ] || { echo "FAIL: K8S_EXEC 为空（fine-test.sh 未导出）"; exit 1; }

$K8S_EXEC cloudrobo --version
$K8S_EXEC cloudrobo --help | grep -q workspace
$K8S_EXEC python3 -c "from cloudrobo_core.sdk import Config, HttpClient; Config(); print('sdk-ok')"

AK_V="$($K8S_EXEC printenv HUAWEI_CLOUD_AK 2>/dev/null || true)"
if [ -z "$AK_V" ]; then
  echo "E2E SKIP: case-cloudrobo live（无 HUAWEI_CLOUD_AK，只跑离线冒烟）"
  echo "E2E PASS: case-cloudrobo"
  exit 0
fi
timeout 90 $K8S_EXEC cloudrobo workspace list
echo "E2E PASS: case-cloudrobo"
