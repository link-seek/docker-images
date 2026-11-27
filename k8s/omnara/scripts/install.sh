#!/usr/bin/env bash
# Install Omnara from git manifests only.
#
# Required environment:
#   REPO          path to a link-seek/docker-images checkout at the reviewed SHA
#   OVERLAY       kustomize overlay to apply (default: k8s/omnara-overlays/kubernetes-provider)
#   SECRET_DIR    directory with bootstrap secrets: swr-pull.yaml and omnara-ua.yaml
#   KUBECTL       optional, default "k3s kubectl"
set -euo pipefail
K="${KUBECTL:-k3s kubectl}"
REPO="${REPO:?REPO is required}"
OVERLAY="${OVERLAY:-k8s/omnara-overlays/kubernetes-provider}"
SECRET_DIR="${SECRET_DIR:?SECRET_DIR is required}"

for f in "$SECRET_DIR/swr-pull.yaml" "$SECRET_DIR/omnara-ua.yaml"; do
  test -f "$f" || { echo "missing bootstrap secret: $f"; exit 1; }
done

echo "== namespace =="
$K apply -f "$REPO/k8s/omnara/namespace.yaml"

echo "== bootstrap secrets =="
$K apply -f "$SECRET_DIR/swr-pull.yaml"
$K apply -f "$SECRET_DIR/omnara-ua.yaml"

echo "== overlay: $OVERLAY =="
$K apply -k "$REPO/$OVERLAY"

echo "== wait for Infisical to sync omnara-env =="
for i in $(seq 1 60); do
  if $K -n omnara get secret omnara-env >/dev/null 2>&1; then
    echo "omnara-env present"
    break
  fi
  sleep 5
  test "$i" -lt 60 || { echo "FAIL: omnara-env not synced after 300s"; exit 1; }
done

echo "== wait for postgres =="
$K -n omnara rollout status statefulset/postgres --timeout=300s

echo "== wait for one-shot jobs =="
$K -n omnara wait --for=condition=complete job/migrate --timeout=900s
$K -n omnara wait --for=condition=complete job/rustfs-init --timeout=900s

echo "== wait for services =="
for d in api worker maintenance web redis rustfs; do
  $K -n omnara rollout status "deployment/$d" --timeout=300s
done

echo "install complete"
