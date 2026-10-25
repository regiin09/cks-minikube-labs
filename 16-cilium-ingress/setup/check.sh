#!/usr/bin/env bash
# Grader. Runs INSIDE the node as root (check.ps1 copies it in, runs it, deletes it).
# Checks the Secret + Ingress specs AND real traffic through the Cilium Ingress (Envoy).
pass=0; total=0
ok()  { total=$((total+1)); pass=$((pass+1)); printf '  \e[32m[PASS]\e[0m %s\n' "$1"; }
bad() { total=$((total+1));                   printf '  \e[31m[FAIL]\e[0m %s\n' "$1"; }
t()   { if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi; }
H=shop.example.local
fp()  { openssl x509 -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2; }
WANT=$(fp < /opt/course/16/tls.crt); WANT=${WANT:-no-cert-file}   # never matches an empty fingerprint
# spec query: ing <python expression over dict "i" = the Ingress object>
ing() { kubectl -n shop get ingress shop-ingress -o json 2>/dev/null | python3 -c "
import json,sys; i=json.load(sys.stdin); s=i['spec']
ann=i['metadata'].get('annotations',{})
paths=[(r.get('host'),p) for r in s.get('rules',[]) for p in r.get('http',{}).get('paths',[])]
tls=s.get('tls',[])
sys.exit(0 if ($1) else 1)"; }
# shared Cilium Ingress Service (ClusterIP :80/:443, also NodePort 30080/30443)
IP=$(kubectl -n kube-system get svc cilium-ingress -o jsonpath='{.spec.clusterIP}')

echo "Secret shop/shop-tls"
t "exists, type kubernetes.io/tls"                  "[ \"\$(kubectl -n shop get secret shop-tls -o jsonpath='{.type}')\" = kubernetes.io/tls ]"
t "holds the cert from /opt/course/16/tls.crt"      "[ \"\$(kubectl -n shop get secret shop-tls -o jsonpath='{.data.tls\.crt}' | base64 -d | fp)\" = '$WANT' ]"

echo "Ingress shop/shop-ingress"
t "ingressClassName cilium"                         "ing \"s.get('ingressClassName')=='cilium'\""
t "host $H, path / Prefix -> shop-app:80"           "ing \"any(h=='$H' and p.get('path')=='/' and p.get('pathType')=='Prefix' and p['backend'].get('service',{}).get('name')=='shop-app' and p['backend']['service'].get('port',{}).get('number')==80 for h,p in paths)\""
t "tls: hosts [$H], secretName shop-tls"            "ing \"any('$H' in t.get('hosts',[]) and t.get('secretName')=='shop-tls' for t in tls)\""
t "annotation ingress.cilium.io/force-https"        "ing \"ann.get('ingress.cilium.io/force-https') in ('enabled','true')\""

echo "Traffic (via Cilium Ingress Service kube-system/cilium-ingress $IP)"
t "http://$H -> 301 redirect to https"              "curl -s -m5 -o /dev/null -w '%{http_code} %{redirect_url}' -H 'Host: $H' http://$IP/ | grep -Eq '^30[18] https://$H'"
t "https://$H -> 200 from shop-app"                 "curl -sk -m5 --resolve $H:443:$IP https://$H/ | grep -q 'Q16 shop-app'"
t "served cert is the provided one"                 "[ \"\$(echo | openssl s_client -connect $IP:443 -servername $H 2>/dev/null | fp)\" = '$WANT' ]"

echo
echo "Score: $pass / $total"
