#!/usr/bin/env bash
# Verify a fresh install: workloads, jobs, public HTTP, TLS, no trial leftovers.
set -euo pipefail
K="${KUBECTL:-k3s kubectl}"
PUBLIC_URL="${PUBLIC_URL:-https://omnara.linkseek.net.cn}"
S3_URL="${S3_URL:-https://omnara-s3.linkseek.net.cn}"

echo "== pods =="
$K -n omnara get pods

echo "== jobs =="
$K -n omnara get jobs
$K -n omnara wait --for=condition=complete job/migrate --timeout=60s
$K -n omnara wait --for=condition=complete job/rustfs-init --timeout=60s

echo "== trial leftovers (must be empty) =="
if $K -n omnara get deploy api-trial worker-trial maintenance-trial >/dev/null 2>&1; then
  echo "FAIL: trial deployments still exist"
  exit 1
fi
echo "none"

echo "== public endpoints =="
curl -fsS -o /dev/null -w "app=%{http_code}\n" "$PUBLIC_URL/"
curl -fsS -o /dev/null -w "healthz=%{http_code}\n" "$PUBLIC_URL/healthz"
S3_CODE=$(curl -sS -o /dev/null -w "%{http_code}" "$S3_URL/")
case "$S3_CODE" in
  200|403) echo "s3=$S3_CODE" ;;
  *) echo "FAIL: s3=$S3_CODE"; exit 1 ;;
esac

echo "== TLS =="
echo | openssl s_client -connect "${PUBLIC_URL#https://}:443" -servername "${PUBLIC_URL#https://}" 2>/dev/null \
  | openssl x509 -noout -subject -dates

echo "verify complete"
