#!/usr/bin/env bash
# Runs INSIDE the node. Pulls the Cilium images before helm install, with retries,
# because quay.io lookups from Docker Desktop sometimes fail for a few minutes.
for img in "$@"; do
  for try in 1 2 3 4 5 6 7 8; do
    if docker pull -q "$img" >/dev/null 2>&1; then echo "  pulled ${img%%@*}"; break; fi
    echo "  retry $try: ${img%%@*}"; sleep 15
  done
done
