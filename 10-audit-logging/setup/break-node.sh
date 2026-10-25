#!/usr/bin/env bash
# Runs INSIDE the node (as root). Leaves a basic audit policy in /etc/kubernetes/logpolicy,
# an empty log dir, and namespace "web". Auditing itself is NOT enabled (that's the task).
set -euo pipefail
KC="--kubeconfig=/etc/kubernetes/admin.conf"
KBIN="/var/lib/minikube/binaries/$(ls /var/lib/minikube/binaries | sort -V | tail -1)/kubectl"

echo ">> basic audit policy in /etc/kubernetes/logpolicy"
mkdir -p /etc/kubernetes/logpolicy
cp /tmp/q10/sample-policy.yaml /etc/kubernetes/logpolicy/sample-policy.yaml
chmod 600 /etc/kubernetes/logpolicy/sample-policy.yaml

echo ">> log dir /var/log/kubernetes (empty)"
mkdir -p /var/log/kubernetes
rm -f /var/log/kubernetes/audit-logs*

echo ">> namespace web"
$KBIN $KC get ns web >/dev/null 2>&1 || $KBIN $KC create ns web >/dev/null

echo ">> done. Node is ready for the question."
