#!/usr/bin/env bash
# Runs INSIDE the worker node (as root). Replaces minikube's kubelet with apt-managed
# kubeadm/kubelet/kubectl at the OLD version, held, like a kubeadm-installed exam node.
# Usage: worker.sh <old-version e.g. 1.35.0> <base64 of master root ssh pubkey>
set -euo pipefail
OLD="$1"; PUB=$(echo "$2" | base64 -d)
MINOR=$(echo "$OLD" | cut -d. -f1,2)          # 1.35

grep -q nocompatible /etc/vim/vimrc.tiny || \
  printf 'set nocompatible\nset backspace=indent,eol,start\n' >> /etc/vim/vimrc.tiny

echo ">> allow ssh from the control plane (user docker, then sudo -i)"
grep -qF "$PUB" /home/docker/.ssh/authorized_keys || echo "$PUB" >> /home/docker/.ssh/authorized_keys

echo ">> apt repo pkgs.k8s.io v${MINOR}"
apt-get update -qq >/dev/null
apt-get install -y -qq gnupg apt-transport-https >/dev/null
mkdir -p /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${MINOR}/deb/Release.key" | \
  gpg --dearmor --batch --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${MINOR}/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list
apt-get update -qq >/dev/null

echo ">> install kubeadm/kubelet/kubectl ${OLD} and hold them"
apt-get install -y -qq --allow-downgrades \
  "kubeadm=${OLD}-1.1" "kubelet=${OLD}-1.1" "kubectl=${OLD}-1.1" >/dev/null 2>&1
apt-mark hold kubeadm kubelet kubectl >/dev/null

echo ">> point the kubelet unit at /usr/bin/kubelet (the apt one)"
sed -i 's|^ExecStart=/var/lib/minikube/binaries/[^/]*/kubelet|ExecStart=/usr/bin/kubelet|' \
  /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
systemctl daemon-reload
systemctl restart kubelet
sleep 5
/usr/bin/kubelet --version
echo ">> worker done"
