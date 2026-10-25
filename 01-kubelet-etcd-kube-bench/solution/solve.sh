#!/usr/bin/env bash
# SOLUTION (run as root on the node). Same edits the README answer makes by hand in vi.
set -euo pipefail

# kubelet: CIS 4.2.1 + 4.2.2
sed -i '/^  anonymous:/{n;s/enabled: true/enabled: false/}' /var/lib/kubelet/config.yaml
sed -i 's/^  mode: AlwaysAllow/  mode: Webhook/' /var/lib/kubelet/config.yaml
systemctl daemon-reload
systemctl restart kubelet

# etcd flags: CIS 2.2, 2.3, 2.6 (edit the existing lines, don't add new ones)
sed -i -e '/--auto-tls=true/d' -e '/--peer-auto-tls=true/d' \
       -e 's/--client-cert-auth=false/--client-cert-auth=true/' /etc/kubernetes/manifests/etcd.yaml

# etcd data dir: CIS 1.1.11 + 1.1.12
DD=$(ps -eo args | grep '^etcd ' | grep -o -- '--data-dir=[^ ]*' | cut -d= -f2)
id etcd >/dev/null 2>&1 || useradd -r -s /usr/sbin/nologin etcd
chown -R etcd:etcd "$DD"
chmod 700 "$DD"

echo ">> waiting for etcd + API server"
sleep 20
until kubectl get --raw /readyz >/dev/null 2>&1; do sleep 3; done
kube-bench run --targets master,etcd,node 2>/dev/null | grep -E ' (1\.1\.1[12]|2\.[236]|4\.2\.[12]) '
