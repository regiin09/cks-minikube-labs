#!/usr/bin/env bash
# Runs INSIDE the minikube node (as root). Installs bom, drops the Deployment manifest
# in /opt/course/05, and pre-pulls the alpine images.
# Usage: break-node.sh <bad-container-name>
set -euo pipefail
BAD="$1"
BOM_VERSION=v0.8.0

echo ">> installing bom ${BOM_VERSION}"
if ! command -v bom >/dev/null 2>&1; then
  curl -fsSL -o /usr/local/bin/bom \
    "https://github.com/kubernetes-sigs/bom/releases/download/${BOM_VERSION}/bom-amd64-linux"
  chmod +x /usr/local/bin/bom
fi

echo ">> task files in /opt/course/05"
mkdir -p /opt/course/05
cp /tmp/q05/alpine-deployment.yaml /opt/course/05/alpine-deployment.yaml
echo -n "$BAD" | base64 > /var/lib/minikube/.q05            # grader key

echo ">> pre-pulling alpine images"
for t in 3.19.1 3.20.0 3.21.3; do docker pull -q "alpine:$t" >/dev/null; done
echo ">> done. Node is ready for the question."
