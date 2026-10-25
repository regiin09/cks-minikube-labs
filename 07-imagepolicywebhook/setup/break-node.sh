#!/usr/bin/env bash
# Runs INSIDE the node (as root). Starts the image scanner (HTTPS webhook backend) and
# leaves an INCOMPLETE ImagePolicyWebhook config in /etc/kubernetes/epconfig.
set -euo pipefail
EP=/etc/kubernetes/epconfig
SC=/etc/image-scanner
HOST=image-scanner.local

echo ">> scanner hostname $HOST -> 127.0.0.1"
grep -q " $HOST" /etc/hosts || echo "127.0.0.1 $HOST" >> /etc/hosts

echo ">> certificates (scanner CA, scanner server cert, apiserver client cert)"
mkdir -p "$SC" "$EP" /var/log/imagepolicy
cd "$SC"
openssl req -x509 -newkey rsa:2048 -nodes -days 365 -subj "/CN=image-scanner-ca" \
  -keyout ca.key -out ca.crt 2>/dev/null
openssl req -newkey rsa:2048 -nodes -subj "/CN=$HOST" -keyout server.key -out server.csr 2>/dev/null
printf "subjectAltName=DNS:%s,IP:127.0.0.1\n" "$HOST" > san.ext
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 365 \
  -extfile san.ext -out server.crt 2>/dev/null
openssl req -newkey rsa:2048 -nodes -subj "/CN=kube-apiserver" -keyout "$EP/apiserver-client.key" \
  -out client.csr 2>/dev/null
openssl x509 -req -in client.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 365 \
  -out "$EP/apiserver-client.crt" 2>/dev/null
cp ca.crt "$EP/scanner-ca.crt"

echo ">> scanner service on :8081"
cp /tmp/q07/image-scanner.py /usr/local/bin/image-scanner.py
cat > /etc/systemd/system/image-scanner.service <<'EOF'
[Unit]
Description=Container image scanner (ImagePolicyWebhook backend)
After=network.target
[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/image-scanner.py
Restart=always
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now image-scanner >/dev/null 2>&1

echo ">> incomplete config in $EP"
cat > "$EP/admission_configuration.json" <<EOF
{
  "apiVersion": "apiserver.config.k8s.io/v1",
  "kind": "AdmissionConfiguration",
  "plugins": [
    {
      "name": "ImagePolicyWebhook",
      "configuration": {
        "imagePolicy": {
          "kubeConfigFile": "$EP/kubeconfig.yaml",
          "allowTTL": 50,
          "denyTTL": 50,
          "retryBackoff": 500,
          "defaultAllow": true
        }
      }
    }
  ]
}
EOF
cat > "$EP/kubeconfig.yaml" <<EOF
apiVersion: v1
kind: Config
clusters:
- name: image-scanner
  cluster:
    certificate-authority: $EP/scanner-ca.crt
    server:
users:
- name: kube-apiserver
  user:
    client-certificate: $EP/apiserver-client.crt
    client-key: $EP/apiserver-client.key
contexts:
- name: image-scanner
  context:
    cluster: image-scanner
    user: kube-apiserver
current-context: image-scanner
EOF

echo ">> test resource"
mkdir -p /root/q07
cp /tmp/q07/vulnerable-resource.yml /root/q07/vulnerable-resource.yml

sleep 2
curl -s --cacert "$SC/ca.crt" -X POST -d '{"spec":{"containers":[{"image":"nginx:latest"}]}}' \
  "https://$HOST:8081/image_policy" | grep -q '"allowed": false' && echo ">> scanner is up and rejecting :latest"
echo ">> done. Node is ready for the question."
