#!/usr/bin/env bash
# Runs INSIDE the minikube node (as root). Drops the Deployment manifest in /opt/course/14
# and pre-pulls the image. (The namespace + Deployment are applied by setup.ps1.)
set -euo pipefail

echo ">> task file /opt/course/14/deployment.yaml"
mkdir -p /opt/course/14
cp /tmp/q14/deployment.yaml /opt/course/14/deployment.yaml

echo ">> pre-pulling nginxinc/nginx-unprivileged:1.27-alpine"
docker pull -q nginxinc/nginx-unprivileged:1.27-alpine >/dev/null
echo ">> done. Node is ready for the question."
