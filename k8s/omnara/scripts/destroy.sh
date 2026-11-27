#!/usr/bin/env bash
# Destroy the Omnara production namespaces. Backups must already be verified.
set -euo pipefail
K="${KUBECTL:-k3s kubectl}"

for ns in omnara omnara-machines; do
  if $K get namespace "$ns" >/dev/null 2>&1; then
    echo "deleting namespace $ns"
    $K delete namespace "$ns" --wait=true --timeout=300s
  else
    echo "namespace $ns already absent"
  fi
done

# local-path PVs are Delete; NFS memory-data is Retain and may be Released.
echo "remaining PVs for omnara claims:"
$K get pv -o custom-columns=NAME:.metadata.name,CLAIM:.spec.claimRef.name,POLICY:.spec.persistentVolumeReclaimPolicy,STATUS:.status.phase \
  | grep -E "memory-data|postgres|redis|rustfs" || true
