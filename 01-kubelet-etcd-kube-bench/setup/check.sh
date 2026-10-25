#!/usr/bin/env bash
# Grader. Runs INSIDE the node as root (check.ps1 copies it in, runs it, deletes it).
# kube-bench results for the 7 target checks + "is the fix real and the cluster healthy".
KC=/var/lib/kubelet/config.yaml
EM=/etc/kubernetes/manifests/etcd.yaml
pass=0; total=0
ok()  { total=$((total+1)); pass=$((pass+1)); printf '  \e[32m[PASS]\e[0m %s\n' "$1"; }
bad() { total=$((total+1));                   printf '  \e[31m[FAIL]\e[0m %s\n' "$1"; }
t()   { if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi; }
DD=$(ps -eo args | grep '^etcd ' | grep -o -- '--data-dir=[^ ]*' | cut -d= -f2)
DD=${DD:-/var/lib/minikube/etcd}

echo "Cluster health (checked first: kube-bench reads the RUNNING processes)"
t "kubelet active"                                 "systemctl is-active kubelet"
t "etcd running"                                   "pgrep -x etcd"
t "API server healthy"                             "kubectl get --raw /readyz"
t "node Ready"                                     "kubectl get nodes --no-headers | awk '{print \$2}' | grep -qx Ready"

KB=$(kube-bench run --targets master,etcd,node 2>/dev/null)
kb() { echo "$KB" | grep -qE "^\[PASS\] $1 "; }
echo "kube-bench (CIS)"
t "4.2.1 kubelet anonymous auth disabled"          "kb 4.2.1"
t "4.2.2 kubelet authorization not AlwaysAllow"    "kb 4.2.2"
t "2.2   etcd --client-cert-auth=true"             "kb 2.2"
t "2.3   etcd --auto-tls not true"                 "kb 2.3"
t "2.6   etcd --peer-auto-tls not true"            "kb 2.6"
t "1.1.11 etcd data dir 700"                       "kb 1.1.11"
t "1.1.12 etcd data dir etcd:etcd"                 "kb 1.1.12"

echo "Done properly"
t "kubelet authorization mode is exactly Webhook"  "grep -A1 '^authorization:' $KC | grep -qE 'mode: *Webhook'"
t "no duplicate/quoted flags in etcd.yaml"         "[ \$(grep -c -- '--client-cert-auth' $EM) = 1 ] && ! grep -q -- '=\"' $EM"
t "user etcd exists"                               "id etcd"
t "no stray files in /etc/kubernetes/manifests"    "[ -z \"\$(ls -A /etc/kubernetes/manifests | grep -vE '^(etcd|kube-apiserver|kube-controller-manager|kube-scheduler)\\.yaml\$')\" ]"

echo
echo "Score: $pass / $total"
