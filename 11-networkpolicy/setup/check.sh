#!/usr/bin/env bash
# Grader. Runs INSIDE the node as root (check.ps1 copies it in, runs it, deletes it).
# Checks the NetworkPolicy specs AND real traffic through Calico.
read -r A O < <(base64 -d /var/lib/minikube/.q11 2>/dev/null)
pass=0; total=0
ok()  { total=$((total+1)); pass=$((pass+1)); printf '  \e[32m[PASS]\e[0m %s\n' "$1"; }
bad() { total=$((total+1));                   printf '  \e[31m[FAIL]\e[0m %s\n' "$1"; }
t()   { if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi; }
code() { kubectl -n "$1" exec deploy/client -- curl -sk -o /dev/null -w '%{http_code}' --connect-timeout 3 -m 5 "$2" 2>/dev/null; }
# spec query: py <name> <python expression over dict "s" = .spec>
py() { kubectl -n prod get netpol "$1" -o json 2>/dev/null | A="$A" python3 -c "
import json,os,sys; s=json.load(sys.stdin)['spec']; A=os.environ['A']
ing=s.get('ingress') or []; pt=s.get('policyTypes') or []
peers=[p for r in ing for p in (r.get('from') or [])]
def nsA(p):   # this peer matches exactly namespace A (all its Pods)
    n=p.get('namespaceSelector')
    if n is None or p.get('ipBlock') or (p.get('podSelector') or {}): return False
    ml=n.get('matchLabels') or {}; me=n.get('matchExpressions') or []
    byL = ml=={'kubernetes.io/metadata.name':A} and not me
    byE = not ml and len(me)==1 and me[0].get('key')=='kubernetes.io/metadata.name' and me[0].get('operator')=='In' and me[0].get('values')==[A]
    return byL or byE
sys.exit(0 if ($2) else 1)"; }

echo "Allowed namespace this run: $A   (not allowed: $O)"
echo "Policy 1: prod/deny-all-ingress"
t "exists, podSelector {} (all Pods)"               "py deny-all-ingress \"s.get('podSelector')in({},None)\""
t "policyTypes [Ingress], no ingress rules"         "py deny-all-ingress \"pt==['Ingress'] and not ing\""

echo "Policy 2: prod/allow-from-$A"
t "exists, podSelector {} (all Pods)"               "py allow-from-$A \"s.get('podSelector')in({},None)\""
t "policyTypes [Ingress] (egress not touched)"      "py allow-from-$A \"pt==['Ingress']\""
t "namespaceSelector kubernetes.io/metadata.name=$A" "py allow-from-$A \"any(nsA(p) for p in peers)\""
t "every source is ONLY namespace $A (no OR-dash podSelector, no {})" "py allow-from-$A \"ing and all(r.get('from') for r in ing) and all(nsA(p) for p in peers)\""
t "no NetworkPolicy in prod restricts egress"       "! kubectl -n prod get netpol -o jsonpath='{.items[*].spec.policyTypes}' | grep -q Egress"

echo "Traffic"
t "$A -> web.prod works"                            "[ \"\$(code $A http://web.prod)\" = 200 ]"
t "$A -> api.prod works"                            "[ \"\$(code $A http://api.prod)\" = 200 ]"
t "$O -> web.prod blocked"                          "[ \"\$(code $O http://web.prod)\" = 000 ]"
t "$O -> api.prod blocked"                          "[ \"\$(code $O http://api.prod)\" = 000 ]"
t "prod client -> web.prod blocked (same namespace)" "[ \"\$(code prod http://web.prod)\" = 000 ]"
t "prod client -> api.prod blocked (same namespace)" "[ \"\$(code prod http://api.prod)\" = 000 ]"
t "prod egress: DNS + web.$O works"                 "[ \"\$(code prod http://web.$O)\" = 200 ]"
t "prod egress: kube-apiserver reachable"           "[ \"\$(code prod https://kubernetes.default.svc/version)\" != 000 ]"

echo
echo "Score: $pass / $total"
