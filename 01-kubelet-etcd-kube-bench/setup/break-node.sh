#!/usr/bin/env bash
# Runs INSIDE the minikube node (as root). Puts the node into the insecure
# starting state of the task, and installs kube-bench.
set -euo pipefail

KUBE_BENCH_VERSION=0.16.0
KUBELET_CONF=/var/lib/kubelet/config.yaml
ETCD_MANIFEST=/etc/kubernetes/manifests/etcd.yaml
ETCD_DATA_DIR=/var/lib/minikube/etcd

echo ">> vi: arrow keys + backspace (vim.tiny defaults to 'compatible')"
grep -q nocompatible /etc/vim/vimrc.tiny || printf 'set nocompatible\nset backspace=indent,eol,start\n' >> /etc/vim/vimrc.tiny

echo ">> installing kube-bench v${KUBE_BENCH_VERSION}"
if ! command -v kube-bench >/dev/null 2>&1; then
  curl -fsSL -o /tmp/kube-bench.deb \
    "https://github.com/aquasecurity/kube-bench/releases/download/v${KUBE_BENCH_VERSION}/kube-bench_${KUBE_BENCH_VERSION}_linux_amd64.deb"
  dpkg -i /tmp/kube-bench.deb >/dev/null
  rm -f /tmp/kube-bench.deb
fi

echo ">> kubelet: enable anonymous auth, authorization AlwaysAllow"
cp -n "$KUBELET_CONF" /root/kubelet-config.yaml.orig
# anonymous.enabled is the first "enabled:" under authentication
sed -i '/^  anonymous:/{n;s/enabled: false/enabled: true/}' "$KUBELET_CONF"
sed -i 's/^  mode: Webhook/  mode: AlwaysAllow/' "$KUBELET_CONF"
systemctl daemon-reload
systemctl restart kubelet

echo ">> etcd: client-cert-auth=false, auto-tls=true, peer-auto-tls=true"
cp -n "$ETCD_MANIFEST" /root/etcd.yaml.orig
sed -i 's/--client-cert-auth=true/--client-cert-auth=false/' "$ETCD_MANIFEST"
grep -q -- '--auto-tls=' "$ETCD_MANIFEST" || \
  sed -i 's|^    - --cert-file=|    - --auto-tls=true\n    - --cert-file=|' "$ETCD_MANIFEST"
grep -q -- '--peer-auto-tls=' "$ETCD_MANIFEST" || \
  sed -i 's|^    - --peer-cert-file=|    - --peer-auto-tls=true\n    - --peer-cert-file=|' "$ETCD_MANIFEST"

echo ">> etcd data dir: loosen permissions, no etcd user"
chmod 755 "$ETCD_DATA_DIR"
chown root:root "$ETCD_DATA_DIR"
if id etcd >/dev/null 2>&1; then userdel etcd; fi
if getent group etcd >/dev/null 2>&1; then groupdel etcd; fi

echo ">> waiting for etcd to restart with the new flags"
for i in $(seq 1 90); do
  if pgrep -af '^etcd ' | grep -q -- '--auto-tls=true'; then break; fi
  sleep 2
done
echo ">> waiting for the API server to come back"
for i in $(seq 1 60); do
  if curl -sk https://127.0.0.1:8443/readyz >/dev/null 2>&1; then break; fi
  sleep 2
done

echo ">> done. Node is ready for the question."
