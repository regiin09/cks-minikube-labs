#!/usr/bin/env bash
# Runs INSIDE the control-plane node (as root). Lets root "ssh node01" to the worker.
# Usage: master.sh <worker-ip> <worker-node-name>
# Prints the root public key (base64) as the LAST line, for worker.sh.
set -euo pipefail
IP="$1"; NAME="$2"

mkdir -p /root/.ssh && chmod 700 /root/.ssh
[ -f /root/.ssh/id_ed25519 ] || ssh-keygen -q -t ed25519 -N '' -f /root/.ssh/id_ed25519
cat > /root/.ssh/config <<EOF
Host node01 ${NAME}
  HostName ${IP}
  User docker
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  LogLevel ERROR
EOF
chmod 600 /root/.ssh/config
grep -q " node01" /etc/hosts || echo "${IP} node01" >> /etc/hosts

base64 -w0 /root/.ssh/id_ed25519.pub; echo
