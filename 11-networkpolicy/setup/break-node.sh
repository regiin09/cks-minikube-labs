#!/usr/bin/env bash
# Runs INSIDE the node (as root). Writes the task file and the grader key.
# Usage: break-node.sh <allowed-namespace> <other-namespace>
set -euo pipefail
ALLOWED="$1"; OTHER="$2"
mkdir -p /opt/course/11
cat > /opt/course/11/task.txt <<TXT
Namespace prod runs Deployments web and api (with Services) and a client.

1. Create NetworkPolicy "deny-all-ingress" in namespace prod that denies ALL
   ingress traffic to ALL Pods in prod.
2. Create NetworkPolicy "allow-from-${ALLOWED}" in namespace prod that allows
   ingress to all Pods in prod ONLY from Pods in namespace "${ALLOWED}".
   Use the label kubernetes.io/metadata.name to select the namespace.
3. Do not restrict egress. Pods in other namespaces (e.g. "${OTHER}") and Pods
   inside prod itself must not reach the prod Pods.
TXT
echo -n "${ALLOWED} ${OTHER}" | base64 > /var/lib/minikube/.q11     # grader key
echo ">> done. Task: /opt/course/11/task.txt"
