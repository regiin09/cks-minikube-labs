#!/usr/bin/env bash
# SOLUTION (run as root on the node). Same edits the README answer makes by hand in vi.
# Usage: solve.sh <path-to-solution-policy>   (defaults to ./sample-policy.yaml)
set -euo pipefail
POL=/etc/kubernetes/logpolicy/sample-policy.yaml
LOG=/var/log/kubernetes/audit-logs.txt
M=/etc/kubernetes/manifests/kube-apiserver.yaml
cp $M /root/kube-apiserver.yaml.bak          # backup OUTSIDE the manifests dir

# 1. extend the policy (the README shows the full file)
cp "${1:-sample-policy.yaml}" $POL

# 2. audit flags
sed -i "/- kube-apiserver\$/a\\    - --audit-policy-file=$POL\n    - --audit-log-path=$LOG\n    - --audit-log-maxbackup=2\n    - --audit-log-maxage=10" $M

# 3. mount the policy (read-only) and the log dir (writable)
sed -i "/^    volumeMounts:/a\\    - mountPath: $POL\n      name: audit-policy\n      readOnly: true\n    - mountPath: /var/log/kubernetes\n      name: audit-logs" $M
sed -i "/^  volumes:/a\\  - hostPath:\n      path: $POL\n      type: File\n    name: audit-policy\n  - hostPath:\n      path: /var/log/kubernetes\n      type: DirectoryOrCreate\n    name: audit-logs" $M

echo ">> waiting for the API server to restart"
sleep 20
until kubectl get --raw /readyz >/dev/null 2>&1; do sleep 3; done
ps -eo args | grep -E '^kube-apiserver ' | tr ' ' '\n' | grep audit
tail -c 600 $LOG; echo
