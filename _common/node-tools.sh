#!/usr/bin/env bash
# Runs INSIDE every minikube node (as root). Makes the shell feel like the exam:
# kubectl on PATH, root kubeconfig, bash completion, alias k, working vi arrows.
set -euo pipefail

echo ">> node tools: kubectl, completion, alias k, vim"
KBIN="/var/lib/minikube/binaries/$(ls /var/lib/minikube/binaries | sort -V | tail -1)/kubectl"
ln -sf "$KBIN" /usr/local/bin/kubectl

mkdir -p /root/.kube
cp /etc/kubernetes/admin.conf /root/.kube/config
chmod 600 /root/.kube/config

if [ ! -f /usr/share/bash-completion/bash_completion ]; then
  apt-get update -qq >/dev/null
  apt-get install -y -qq bash-completion >/dev/null
fi

if ! grep -q '# cks-lab' /etc/bash.bashrc; then
  cat >> /etc/bash.bashrc <<'EOF'
# cks-lab: exam-like shell
[ -f /usr/share/bash-completion/bash_completion ] && . /usr/share/bash-completion/bash_completion
source <(kubectl completion bash 2>/dev/null)
alias k=kubectl
complete -o default -F __start_kubectl k
export do="--dry-run=client -o yaml"
EOF
fi

grep -q nocompatible /etc/vim/vimrc.tiny || \
  printf 'set nocompatible\nset backspace=indent,eol,start\n' >> /etc/vim/vimrc.tiny
