#!/usr/bin/env bash
# Grader. Runs INSIDE the node as root (check.ps1 copies it in, runs it, deletes it).
# Checks the policy specs AND real traffic (incl. that a SPIRE handshake happened).
pass=0; total=0
ok()  { total=$((total+1)); pass=$((pass+1)); printf '  \e[32m[PASS]\e[0m %s\n' "$1"; }
bad() { total=$((total+1));                   printf '  \e[31m[FAIL]\e[0m %s\n' "$1"; }
t()   { if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi; }
code() { kubectl -n "$1" exec deploy/client -- curl -s -o /dev/null -w '%{http_code}' --connect-timeout 4 -m 6 "$2" 2>/dev/null; }
# spec query: py <ns> <name> <python expression over dict "s" = .spec>
py() { kubectl -n "$1" get cnp "$2" -o json 2>/dev/null | python3 -c "
import json,sys; s=json.load(sys.stdin)['spec']
ing=s.get('ingress',[]); egd=s.get('egressDeny',[])
sel=s.get('endpointSelector',{}).get('matchLabels',{})
ns=lambda r:[e.get('matchLabels',{}).get('k8s:io.kubernetes.pod.namespace', e.get('matchLabels',{}).get('io.kubernetes.pod.namespace')) for e in r.get('fromEndpoints',[])]
port80=lambda r:any(p.get('port')=='80' and p.get('protocol','TCP').upper() in('TCP','ANY') for tp in r.get('toPorts',[]) for p in tp.get('ports',[]))
sys.exit(0 if ($3) else 1)"; }

echo "Policy 1: payments/api-ingress"
t "exists, selects app=api"                         "py payments api-ingress \"sel.get('app')=='api'\""
t "allows from namespace checkout"                  "py payments api-ingress \"any('checkout' in ns(r) for r in ing)\""
t "on port 80/TCP"                                  "py payments api-ingress \"any(port80(r) for r in ing if 'checkout' in ns(r))\""
t "authentication mode required"                    "py payments api-ingress \"any(r.get('authentication',{}).get('mode')=='required' for r in ing if 'checkout' in ns(r))\""

echo "Policy 2: payments/metrics-from-host"
t "exists, selects app=metrics"                     "py payments metrics-from-host \"sel.get('app')=='metrics'\""
t "allows fromEntities host"                        "py payments metrics-from-host \"any('host' in r.get('fromEntities',[]) for r in ing)\""
t "no mutual auth on the host rule"                 "py payments metrics-from-host \"all(r.get('authentication',{}).get('mode') in (None,'disabled') for r in ing if 'host' in r.get('fromEntities',[]))\""

echo "Policy 3: checkout/deny-world"
t "egressDeny toEntities world"                     "py checkout deny-world \"any('world' in r.get('toEntities',[]) for r in egd)\""

echo "Traffic"
t "checkout  -> api:80 works"                       "[ \"\$(code checkout http://api.payments)\" = 200 ]"
API_ID=$(kubectl -n payments get cep -l app=api -o jsonpath='{.items[0].status.identity.id}')
t "mutual auth happened (SPIRE entry for api)"      "kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg bpf auth list 2>/dev/null | awk '(\$1==\"$API_ID\" || \$2==\"$API_ID\") && \$4==\"spire\"' | grep -q ."
t "marketing -> api:80 blocked"                     "[ \"\$(code marketing http://api.payments)\" != 200 ]"
t "marketing -> metrics:80 blocked"                 "[ \"\$(code marketing http://metrics.payments)\" != 200 ]"
MIP=$(kubectl -n payments get pod -l app=metrics -o jsonpath='{.items[0].status.podIP}')
t "host (node) -> metrics:80 works"                 "[ \"\$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 4 http://$MIP)\" = 200 ]"
t "checkout  -> internet (world) blocked"           "[ \"\$(code checkout https://1.1.1.1)\" = 000 ]"

echo
echo "Score: $pass / $total"
