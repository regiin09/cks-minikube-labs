#!/usr/bin/env bash
# Runs INSIDE the minikube node (as root). Generates the cert + key the task gives you
# in /opt/course/16, plus an unrelated old cert used for a decoy Secret.
set -euo pipefail
D=/opt/course/16
echo ">> cert + key for shop.example.local in $D"
mkdir -p "$D"
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout "$D/tls.key" -out "$D/tls.crt" \
  -subj "/CN=shop.example.local/O=cks-q16" \
  -addext "subjectAltName=DNS:shop.example.local" 2>/dev/null
chmod 600 "$D/tls.key"

echo ">> decoy cert (old-shop.example.local) for Secret shop/shop-tls-old"
openssl req -x509 -newkey rsa:2048 -nodes -days 30 \
  -keyout /tmp/old.key -out /tmp/old.crt \
  -subj "/CN=old-shop.example.local" -addext "subjectAltName=DNS:old-shop.example.local" 2>/dev/null
kubectl create ns shop --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n shop create secret tls shop-tls-old --cert=/tmp/old.crt --key=/tmp/old.key \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
rm -f /tmp/old.key /tmp/old.crt
echo ">> done. Node is ready for the question."
