#!/usr/bin/env bash
# SOLUTION (run as root on the node). Same steps as the README answers.
set -e
# 1. ServiceAccount: no automount
kubectl -n monitoring patch sa stats-monitor-sa -p '{"automountServiceAccountToken": false}'
# 2. Deployment: projected token volume, read-only mount (file + cluster)
cp "$(dirname "$0")/deployment.yaml" /opt/course/13/deployment.yaml
kubectl apply -f /opt/course/13/deployment.yaml
kubectl -n monitoring rollout status deploy/stats-monitor --timeout=120s
