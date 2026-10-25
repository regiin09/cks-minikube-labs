#!/usr/bin/env bash
# Runs INSIDE the node (as root, after node-tools.sh): install istioctl, install Istio
# (minimal profile = istiod only, small requests), pre-pull the images the lab uses.
set -euo pipefail
ISTIO_VERSION=1.31.2

echo ">> istioctl $ISTIO_VERSION"
if ! command -v istioctl >/dev/null 2>&1; then
  curl -fsSL "https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istioctl-${ISTIO_VERSION}-linux-amd64.tar.gz" \
    | tar -xz -C /usr/local/bin istioctl
fi
grep -q 'istioctl completion' /etc/bash.bashrc || echo 'source <(istioctl completion bash 2>/dev/null)' >> /etc/bash.bashrc

echo ">> pre-pulling images"
for i in "docker.io/istio/pilot:$ISTIO_VERSION" "docker.io/istio/proxyv2:$ISTIO_VERSION" \
         nginx:1.27-alpine curlimages/curl:8.11.1; do
  docker pull -q "$i" >/dev/null
done

echo ">> istioctl install (minimal profile) - ~1 min"
istioctl install -y --set profile=minimal \
  --set values.pilot.resources.requests.cpu=100m \
  --set values.pilot.resources.requests.memory=256Mi \
  --set values.global.proxy.resources.requests.cpu=20m \
  --set values.global.proxy.resources.requests.memory=64Mi
kubectl -n istio-system rollout status deploy/istiod --timeout=300s
istioctl version
echo ">> done. Istio is installed; no namespace is in the mesh yet."
