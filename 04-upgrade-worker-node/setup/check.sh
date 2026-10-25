#!/usr/bin/env bash
# Grader. Runs INSIDE the control-plane node as root (check.ps1 copies it in, runs, deletes).
# Usage: check.sh <target-version e.g. 1.35.1> <worker-node-name>
WANT="$1"; W="$2"
K=kubectl
R() { ssh -o BatchMode=yes node01 "sudo $*" 2>/dev/null; }   # run on worker
pass=0; total=0
ok()  { total=$((total+1)); pass=$((pass+1)); printf '  \e[32m[PASS]\e[0m %s\n' "$1"; }
bad() { total=$((total+1));                   printf '  \e[31m[FAIL]\e[0m %s\n' "$1"; }
t()   { if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi; }
CP=$($K get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[0].metadata.name}')

echo "Worker $W"
t "kubelet reports v$WANT"                        "[ \"\$($K get node $W -o jsonpath={.status.nodeInfo.kubeletVersion})\" = v$WANT ]"
t "node Ready"                                    "$K get node $W --no-headers | awk '{print \$2}' | grep -qx Ready"
t "node uncordoned (schedulable)"                 "[ -z \"\$($K get node $W -o jsonpath={.spec.unschedulable})\" ]"
PKG() { R dpkg-query -W "$1" | awk '{print $2}'; }   # installed version, parsed here not over ssh
t "kubeadm package = $WANT-1.1"                   "[ \"\$(PKG kubeadm)\" = $WANT-1.1 ]"
t "kubelet package = $WANT-1.1"                   "[ \"\$(PKG kubelet)\" = $WANT-1.1 ]"
t "kubectl package = $WANT-1.1"                   "[ \"\$(PKG kubectl)\" = $WANT-1.1 ]"
t "kubeadm, kubelet, kubectl held again"          "[ \"\$(R apt-mark showhold | sort | tr '\n' ' ')\" = 'kubeadm kubectl kubelet ' ]"
t "kubelet service running new binary"            "R systemctl is-active kubelet && R /usr/bin/kubelet --version | grep -q v$WANT"

echo "Cluster"
t "control plane $CP still v$WANT"                "[ \"\$($K get node $CP -o jsonpath={.status.nodeInfo.kubeletVersion})\" = v$WANT ]"
t "Deployment web 4/4 ready"                      "[ \"\$($K get deploy web -o jsonpath={.status.readyReplicas})\" = 4 ]"
t "Deployment cache (pinned to worker) 1/1 ready" "[ \"\$($K get deploy cache -o jsonpath={.status.readyReplicas})\" = 1 ]"

echo
echo "Score: $pass / $total"
