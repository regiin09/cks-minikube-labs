#!/usr/bin/env bash
# Grader. Runs INSIDE the node as root (check.ps1 copies it in, runs it, deletes it).
# Checks the Secret + Ingress specs AND real traffic through ingress-nginx.
pass=0; total=0
ok()  { total=$((total+1)); pass=$((pass+1)); printf '  \e[32m[PASS]\e[0m %s\n' "$1"; }
bad() { total=$((total+1));                   printf '  \e[31m[FAIL]\e[0m %s\n' "$1"; }
t()   { if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi; }
H=secure.example.local
fp()  { openssl x509 -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2; }
WANT=$(fp < /opt/course/12/tls.crt)
# spec query: ing <python expression over dict "i" = the Ingress object>
ing() { kubectl -n web get ingress secure-ingress -o json 2>/dev/null | python3 -c "
import json,sys; i=json.load(sys.stdin); s=i['spec']
ann=i['metadata'].get('annotations',{})
paths=[(r.get('host'),p) for r in s.get('rules',[]) for p in r.get('http',{}).get('paths',[])]
tls=s.get('tls',[])
sys.exit(0 if ($1) else 1)"; }
IP=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.spec.clusterIP}')

echo "Secret web/secure-tls"
t "exists, type kubernetes.io/tls"                  "[ \"\$(kubectl -n web get secret secure-tls -o jsonpath='{.type}')\" = kubernetes.io/tls ]"
t "holds the cert from /opt/course/12/tls.crt"      "[ \"\$(kubectl -n web get secret secure-tls -o jsonpath='{.data.tls\.crt}' | base64 -d | fp)\" = '$WANT' ]"

echo "Ingress web/secure-ingress"
t "ingressClassName nginx"                          "ing \"s.get('ingressClassName')=='nginx'\""
t "host $H, path / Prefix -> web-app:80"            "ing \"any(h=='$H' and p.get('path')=='/' and p.get('pathType')=='Prefix' and p['backend'].get('service',{}).get('name')=='web-app' and p['backend']['service'].get('port',{}).get('number')==80 for h,p in paths)\""
t "tls: hosts [$H], secretName secure-tls"          "ing \"any('$H' in t.get('hosts',[]) and t.get('secretName')=='secure-tls' for t in tls)\""
t "annotation ssl-redirect = \"true\""              "ing \"ann.get('nginx.ingress.kubernetes.io/ssl-redirect')=='true'\""

echo "Traffic (via ingress-nginx controller $IP)"
t "http://$H -> 308 redirect to https"              "curl -s -m5 -o /dev/null -w '%{http_code} %{redirect_url}' -H 'Host: $H' http://$IP/ | grep -q '^308 https://$H'"
t "https://$H -> 200 from web-app"                  "curl -sk -m5 --resolve $H:443:$IP https://$H/ | grep -q 'Q12 web-app'"
t "served cert is the provided one (not Fake)"      "[ \"\$(echo | openssl s_client -connect $IP:443 -servername $H 2>/dev/null | fp)\" = '$WANT' ]"

echo
echo "Score: $pass / $total"
