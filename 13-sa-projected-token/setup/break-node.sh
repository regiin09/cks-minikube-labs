#!/usr/bin/env bash
# Runs INSIDE the minikube node (as root). Drops the Deployment manifest in /opt/course/13
# and pre-pulls the image.
set -euo pipefail

echo ">> task files in /opt/course/13"
mkdir -p /opt/course/13
grep -v '^#' /tmp/q13/deployment.yaml > /opt/course/13/deployment.yaml

echo ">> pre-pulling busybox:1.36"
docker pull -q busybox:1.36 >/dev/null
echo ">> done. Node is ready for the question."
