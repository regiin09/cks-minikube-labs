#!/usr/bin/env bash
# Runs INSIDE the node (as root): install the cilium CLI, like an exam node.
set -euo pipefail
CILIUM_CLI_VERSION=v0.20.1
if ! command -v cilium >/dev/null 2>&1; then
  curl -fsSL "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-amd64.tar.gz" \
    | tar -xz -C /usr/local/bin cilium
fi
grep -q 'cilium completion' /etc/bash.bashrc || echo 'source <(cilium completion bash 2>/dev/null)' >> /etc/bash.bashrc
cilium version --client
