#!/usr/bin/env bash
# Grader. Runs INSIDE the node as root (check.ps1 copies it in, runs it, deletes it).
mapfile -t KEY < <(base64 -d /var/lib/minikube/.q09)
SECRET=${KEY[0]}; FP=${KEY[1]}; HASH=${KEY[2]}
C=/opt/course/09
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; total=0
ok()  { total=$((total+1)); pass=$((pass+1)); printf '  \e[32m[PASS]\e[0m %s\n' "$1"; }
bad() { total=$((total+1));                   printf '  \e[31m[FAIL]\e[0m %s\n' "$1"; }
t()   { if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi; }
S="kubectl -n secure get secret $SECRET"

# decode the Secret's keys (if any) for the content checks
$S -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d > $T/crt 2>/dev/null
$S -o jsonpath='{.data.tls\.key}' 2>/dev/null | base64 -d > $T/key 2>/dev/null
xfp() { openssl x509 -in "$1" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2; }

echo "Secret (the name the Deployment references)"
t "Secret exists in namespace secure"                 "$S"
t "type is kubernetes.io/tls"                         "[ \"\$($S -o jsonpath={.type})\" = kubernetes.io/tls ]"
t "has keys tls.crt and tls.key"                      "[ -s $T/crt ] && [ -s $T/key ]"
t "tls.crt is the certificate from $C/web.pem"        "[ -n \"$FP\" ] && [ \"\$(xfp $T/crt)\" = \"$FP\" ]"
t "tls.key is the private key matching that cert"     "[ \"\$(openssl pkey -in $T/key -pubout 2>/dev/null)\" = \"\$(openssl x509 -in $C/web.pem -noout -pubkey)\" ]"

echo "Deployment web (must not be modified)"
t "pod template spec unchanged since setup"           "[ \"\$(kubectl -n secure get deploy web -o jsonpath='{.spec.template.spec}' | sha256sum | cut -d' ' -f1)\" = $HASH ]"
t "Deployment available, all pods Running + Ready"    "[ \"\$(kubectl -n secure get deploy web -o jsonpath={.status.readyReplicas})\" = \"\$(kubectl -n secure get deploy web -o jsonpath={.spec.replicas})\" ]"

echo "Live: HTTPS to Service web"
IP=$(kubectl -n secure get svc web -o jsonpath={.spec.clusterIP} 2>/dev/null)
t "https://web.secure.svc returns 200 (cert verified against web.pem)" \
  "[ \"\$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 --cacert $C/web.pem --resolve web.secure.svc:443:$IP https://web.secure.svc/)\" = 200 ]"
t "served certificate fingerprint = web.pem"          "echo | timeout 5 openssl s_client -connect $IP:443 -servername web.secure.svc 2>/dev/null | openssl x509 -noout -fingerprint -sha256 | grep -q \"=$FP\$\""

echo
echo "Score: $pass / $total"
