#!/usr/bin/env bash
# SOLUTION (run as root on the node). Same edits the README answer makes by hand in vi.
set -euo pipefail
EP=/etc/kubernetes/epconfig
M=/etc/kubernetes/manifests/kube-apiserver.yaml
cp $M /root/kube-apiserver.yaml.bak          # backup OUTSIDE the manifests dir

# 1. implicit deny
sed -i 's/"defaultAllow": true/"defaultAllow": false/' $EP/admission_configuration.json

# 2. point the webhook kubeconfig at the scanner (must be https, full path)
sed -i 's|^    server:.*|    server: https://image-scanner.local:8081/image_policy|' $EP/kubeconfig.yaml

# 3. enable the plugin + config file flag
sed -i 's|--enable-admission-plugins=\([^ ]*\)|--enable-admission-plugins=\1,ImagePolicyWebhook|' $M
sed -i "/--enable-admission-plugins=/a\\    - --admission-control-config-file=$EP/admission_configuration.json" $M

# 4. mount the directory into the apiserver pod
sed -i "/^    volumeMounts:/a\\    - mountPath: $EP\n      name: epconfig\n      readOnly: true" $M
sed -i "/^  volumes:/a\\  - hostPath:\n      path: $EP\n      type: DirectoryOrCreate\n    name: epconfig" $M

echo ">> waiting for the API server to restart"
sleep 20
until kubectl get --raw /readyz >/dev/null 2>&1; do sleep 3; done
kubectl -n kube-system get pod -l component=kube-apiserver

# 5. test
kubectl apply -f /root/q07/vulnerable-resource.yml
sleep 5
kubectl get rs -l app=vulnerable
kubectl describe rs -l app=vulnerable | grep -i -m1 "image scanner\|forbidden" || true
kubectl run allowed --image=nginx:1.27-alpine
tail -3 /var/log/imagepolicy/scanner.log
