#!/usr/bin/env bash
# SOLUTION (run as root on the node). Same edits the README answer makes by hand in vi.
# Variant 1 (default): AuthenticationConfiguration, anonymous only for /livez /readyz /healthz.
# Variant 2 ("flag"):  --anonymous-auth=false and nothing else -> probes get 401, NOT stable.
set -euo pipefail
M=/etc/kubernetes/manifests/kube-apiserver.yaml
cp $M /root/kube-apiserver.yaml.bak          # backup OUTSIDE the manifests dir

# authorization + admission
sed -i 's|--authorization-mode=AlwaysAllow|--authorization-mode=Node,RBAC|' $M
sed -i '/--disable-admission-plugins=NodeRestriction/d' $M
sed -i 's|--enable-admission-plugins=\([^ ]*\)|--enable-admission-plugins=\1,NodeRestriction|' $M

if [ "${1:-}" = flag ]; then
  sed -i 's|--anonymous-auth=true|--anonymous-auth=false|' $M
else
  mkdir -p /etc/kubernetes/authn
  cat > /etc/kubernetes/authn/authn-config.yaml <<'EOC'
apiVersion: apiserver.config.k8s.io/v1
kind: AuthenticationConfiguration
anonymous:
  enabled: true
  conditions:
  - path: /livez
  - path: /readyz
  - path: /healthz
EOC
  sed -i 's|    - --anonymous-auth=true|    - --authentication-config=/etc/kubernetes/authn/authn-config.yaml|' $M
  sed -i "/^    volumeMounts:/a\    - mountPath: /etc/kubernetes/authn\n      name: authn-config\n      readOnly: true" $M
  sed -i "/^  volumes:/a\  - hostPath:\n      path: /etc/kubernetes/authn\n      type: DirectoryOrCreate\n    name: authn-config" $M
fi

echo ">> waiting for the API server to restart"
sleep 30
until kubectl get --raw /readyz >/dev/null 2>&1; do sleep 3; done
kubectl delete clusterrolebinding system:anonymous
curl -sk -o /dev/null -w 'anonymous /api/v1/namespaces -> %{http_code}\n' https://127.0.0.1:8443/api/v1/namespaces
