#!/usr/bin/env bash
# Runs INSIDE the minikube node (as root), after node-tools.sh (kubectl on PATH).
# Generates the cert/key in /opt/course/09, picks a random Secret name, applies the
# Deployment that references the (missing) Secret, and records the grader key.
set -euo pipefail
C=/opt/course/09
NAMES=(web-tls secure-web-tls nginx-https-cert frontend-tls web-serving-cert https-keypair)
SECRET=${NAMES[$((RANDOM % ${#NAMES[@]}))]}

echo ">> certificate + key in $C (web.pem / web-key.pem)"
mkdir -p $C
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout $C/web-key.pem -out $C/web.pem \
  -subj "/CN=web.secure.svc" \
  -addext "subjectAltName=DNS:web,DNS:web.secure,DNS:web.secure.svc,DNS:web.secure.svc.cluster.local" \
  >/dev/null 2>&1
chmod 644 $C/web.pem; chmod 600 $C/web-key.pem

echo ">> pre-pulling nginx:1.27-alpine"
docker pull -q nginx:1.27-alpine >/dev/null

echo ">> applying namespace secure, ConfigMap, Deployment web, Service web"
sed "s/__SECRET__/$SECRET/" /tmp/q09/web.yaml | kubectl apply -f -

# grader key: secret name, cert fingerprint, hash of the pod template spec as created
FP=$(openssl x509 -in $C/web.pem -noout -fingerprint -sha256 | cut -d= -f2)
HASH=$(kubectl -n secure get deploy web -o jsonpath='{.spec.template.spec}' | sha256sum | cut -d' ' -f1)
printf '%s\n%s\n%s\n' "$SECRET" "$FP" "$HASH" | base64 > /var/lib/minikube/.q09
echo ">> done. Node is ready for the question."
