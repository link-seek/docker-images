#!/bin/bash
# CASE-ID: case-maas-reach
# CASE-DESC: MAAS 端点可达（dummy key → 401/403 预期；只验 DNS/TLS，不耗 key）
# CASE-COST: low
set -euo pipefail
[ -n "${K8S_EXEC:-}" ] || { echo "FAIL: K8S_EXEC 为空（fine-test.sh 未导出）"; exit 1; }
$K8S_EXEC python3 -c "
import urllib.request, urllib.error
r = urllib.request.Request('https://api.modelarts-maas.com/v2/models', headers={'Authorization': 'Bearer dummy-preflight'})
try:
    urllib.request.urlopen(r, timeout=20)
    print('UNEXPECTED 200'); raise SystemExit(1)
except urllib.error.HTTPError as e:
    print('MAAS REACHABLE, status', e.code)
    raise SystemExit(0 if e.code in (401, 403) else 1)
"
echo "CASE OK: case-maas-reach"
