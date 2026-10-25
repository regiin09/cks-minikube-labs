#!/usr/bin/env bash
# Runs INSIDE the minikube node (as root). Installs Falco (modern eBPF, systemd),
# then quietly breaks alert output by raising the minimum priority to "error".
# Usage: break-node.sh <bad-deployment-name>
set -euo pipefail
BAD="$1"

echo ">> vi: arrow keys + backspace (vim.tiny defaults to 'compatible')"
grep -q nocompatible /etc/vim/vimrc.tiny || printf 'set nocompatible\nset backspace=indent,eol,start\n' >> /etc/vim/vimrc.tiny

echo ">> installing Falco (modern eBPF) - takes ~1 min"
if ! command -v falco >/dev/null 2>&1; then
  apt-get update -qq >/dev/null
  apt-get install -y -qq gnupg >/dev/null
  curl -fsSL https://falco.org/repo/falcosecurity-packages.asc | \
    gpg --dearmor --batch --yes -o /usr/share/keyrings/falco-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/falco-archive-keyring.gpg] https://download.falco.org/packages/deb stable main" \
    > /etc/apt/sources.list.d/falcosecurity.list
  apt-get update -qq >/dev/null
  FALCO_FRONTEND=noninteractive FALCO_DRIVER_CHOICE=modern_ebpf apt-get install -y -qq falco >/dev/null 2>&1
fi
systemctl mask --now falcoctl-artifact-follow >/dev/null 2>&1 || true   # no rule auto-updates

echo ">> falco.yaml: minimum priority -> error (alerts below error are dropped)"
sed -i 's/^priority: .*/priority: error/' /etc/falco/falco.yaml
cat > /etc/falco/falco_rules.local.yaml <<'EOF'
# Your custom rules go here.
EOF
systemctl restart falco-modern-bpf

echo ">> task dir /opt/course/03"
mkdir -p /opt/course/03
echo -n "$BAD" | base64 > /var/lib/minikube/.q03       # grader key
systemctl is-active falco-modern-bpf >/dev/null && echo ">> falco-modern-bpf is running"
echo ">> done. Node is ready for the question."
