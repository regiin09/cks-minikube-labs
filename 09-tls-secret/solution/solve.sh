#!/usr/bin/env bash
# SOLUTION (run as root on the node). Same steps as the README answers.

# 1. which Secret does the Deployment want?
NAME=$(kubectl -n secure get deploy web -o jsonpath='{.spec.template.spec.volumes[*].secret.secretName}')
echo "Deployment web wants Secret: $NAME"

# 2. create it: type kubernetes.io/tls, keys tls.crt / tls.key
kubectl -n secure create secret tls "$NAME" \
  --cert=/opt/course/09/web.pem --key=/opt/course/09/web-key.pem

# 3. (optional) don't wait for the kubelet mount retry: recreate the pod
kubectl -n secure delete pod -l app=web --wait=false
kubectl -n secure rollout status deploy/web --timeout=120s
