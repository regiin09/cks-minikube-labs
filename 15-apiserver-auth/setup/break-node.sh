#!/usr/bin/env bash
# Runs INSIDE the node (as root). Makes the kube-apiserver insecure:
# anonymous auth on, authorization AlwaysAllow, NodeRestriction off (randomly: just removed,
# or removed AND put in --disable-admission-plugins), plus a CRB giving anonymous cluster-admin.
set -euo pipefail
M=/etc/kubernetes/manifests/kube-apiserver.yaml
KUBECTL="/var/lib/minikube/binaries/$(ls /var/lib/minikube/binaries | sort -V | tail -1)/kubectl"
KC=/etc/kubernetes/admin.conf

echo ">> kube-apiserver: anonymous-auth=true, authorization-mode=AlwaysAllow, NodeRestriction off"
sed -i 's|^    - --authorization-mode=.*|    - --anonymous-auth=true\n    - --authorization-mode=AlwaysAllow|' "$M"
sed -i -e 's|\(--enable-admission-plugins=.*\),NodeRestriction|\1|' \
       -e 's|\(--enable-admission-plugins=\)NodeRestriction,|\1|' "$M"
if [ $((RANDOM % 2)) = 1 ]; then
  sed -i 's|^    - --enable-admission-plugins=|    - --disable-admission-plugins=NodeRestriction\n    - --enable-admission-plugins=|' "$M"
fi

echo ">> waiting for the API server to restart with the new flags"
for i in $(seq 1 90); do
  if ps -eo args | grep '^kube-apiserver' | grep -q -- '--authorization-mode=AlwaysAllow'; then break; fi
  sleep 2
done
for i in $(seq 1 90); do
  if $KUBECTL --kubeconfig $KC get --raw /readyz >/dev/null 2>&1; then break; fi
  sleep 2
done

echo ">> ClusterRoleBinding system:anonymous -> cluster-admin"
$KUBECTL --kubeconfig $KC apply -f /tmp/q15/crb-system-anonymous.yaml

# NOTE (verified on v1.35): with AlwaysAllow the apiserver silently resets anonymous-auth to
# false ("AnonymousAuth is not allowed with the AlwaysAllow authorizer"), so its own HTTPS
# probes get 401 and the pod sits at 0/1 and gets restarted every ~4 min. That is expected.
echo ">> starting state: pod kube-apiserver is 0/1 and restarts every ~4 min (see README, Answers)"
echo ">> done. Node is ready for the question."
