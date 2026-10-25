#!/usr/bin/env bash
# Grader. Runs INSIDE the node as root (check.ps1 copies it in, runs it, deletes it).
# Checks the apiserver manifest, the RUNNING apiserver (process flags + container mounts),
# and live audit behaviour: makes fresh requests and reads the level each one was logged at.
POL=/etc/kubernetes/logpolicy/sample-policy.yaml
LOG=/var/log/kubernetes/audit-logs.txt
M=/etc/kubernetes/manifests/kube-apiserver.yaml
MD=/etc/kubernetes/manifests
CERTS=/var/lib/minikube/certs
R=$RANDOM
T=$(mktemp -d)
pass=0; total=0
ok()  { total=$((total+1)); pass=$((pass+1)); printf '  \e[32m[PASS]\e[0m %s\n' "$1"; }
bad() { total=$((total+1));                   printf '  \e[31m[FAIL]\e[0m %s\n' "$1"; }
t()   { if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi; }
flag() { grep -qE -- "^ *- --$1=\"?$2\"? *\$" $M; }

echo "kube-apiserver manifest ($M)"
t "--audit-policy-file=$POL"                   "flag audit-policy-file $POL"
t "--audit-log-path=$LOG"                      "flag audit-log-path $LOG"
t "--audit-log-maxbackup=2"                    "flag audit-log-maxbackup 2"
t "--audit-log-maxage=10"                      "flag audit-log-maxage 10"
t "no backup/extra files inside $MD/"          "[ -z \"\$(ls -A $MD | grep -vxE '(etcd|kube-apiserver|kube-controller-manager|kube-scheduler)\.yaml')\" ]"

echo "Running kube-apiserver"
t "API server healthy"                         "kubectl get --raw /readyz"
PS=$(ps -eo args | grep -E '^kube-apiserver ' | tr ' ' '\n')
t "running process has the audit flags (ps)"   "echo \"\$PS\" | grep -qx -- '--audit-policy-file=$POL' && echo \"\$PS\" | grep -qx -- '--audit-log-path=$LOG' && echo \"\$PS\" | grep -qx -- '--audit-log-maxbackup=2' && echo \"\$PS\" | grep -qx -- '--audit-log-maxage=10'"
CID=$(docker ps -q --filter name=k8s_kube-apiserver_ | awk 'NR==1')
# mnt <path-inside-container> <rw|ro>: a hostPath mount covers the path, maps to the same host path
mnt() { docker inspect "$CID" | python3 -c '
import json, sys
p, need_rw = sys.argv[1], sys.argv[2] == "rw"
for m in json.load(sys.stdin)[0]["Mounts"]:
    d = m["Destination"].rstrip("/")
    if d and (p == d or p.startswith(d + "/")) and m["Source"].rstrip("/") + p[len(d):] == p and (m["RW"] or not need_rw):
        sys.exit(0)
sys.exit(1)' "$1" "$2"; }
t "policy file mounted into the container (hostPath)"          "mnt $POL ro"
t "log location mounted WRITABLE into the container (hostPath)" "mnt $LOG rw"

echo "Audit policy ($POL)"
t "has a secrets rule scoped to namespace web" "grep -vE '^ *#' $POL | grep -q secrets && grep -vE '^ *#' $POL | grep -qw web"
t "covers the extensions API group"            "grep -vE '^ *#' $POL | grep -qE 'group: *.?extensions'"

echo "Live audit log ($LOG)"
OFF=$(stat -c %s $LOG 2>/dev/null || echo 0)
kubectl create ns q10-ns-$R >/dev/null 2>&1
kubectl -n web create secret generic q10-sec-$R --from-literal=pw=q10 >/dev/null 2>&1
kubectl -n default create configmap q10-cm-$R --from-literal=k=v >/dev/null 2>&1
kubectl -n default create role q10-role-$R --verb=get --resource=pods >/dev/null 2>&1
# a client that really is the user system:kube-proxy (cert signed by the cluster CA)
openssl req -newkey rsa:2048 -nodes -subj "/CN=system:kube-proxy" -keyout $T/kp.key -out $T/kp.csr 2>/dev/null
openssl x509 -req -in $T/kp.csr -CA $CERTS/ca.crt -CAkey $CERTS/ca.key -CAserial $T/ca.srl -CAcreateserial -days 1 -out $T/kp.crt 2>/dev/null
KP="kubectl --kubeconfig=/dev/null --server=https://127.0.0.1:8443 --certificate-authority=$CERTS/ca.crt --client-certificate=$T/kp.crt --client-key=$T/kp.key"
$KP get services -A -o name >/dev/null 2>&1
timeout 4 $KP get services -A --watch -o name >/dev/null 2>&1
timeout 4 $KP get endpoints -A --watch -o name >/dev/null 2>&1
sleep 2
# ev: print "<verb> <user> <resource> <name> <level>" for every event written during this check
ev() { [ -f $LOG ] || return 0; python3 -c '
import json, sys
f = open(sys.argv[1]); off = int(sys.argv[2])
f.seek(off if off <= f.seek(0, 2) else 0)
for line in f:
    try: e = json.loads(line)
    except ValueError: continue
    o = e.get("objectRef") or {}
    name = o.get("name") or ((e.get("requestObject") or {}).get("metadata") or {}).get("name") or "-"
    print(e.get("verb"), e.get("user", {}).get("username"), o.get("resource", "-"), name, e.get("level"))' $LOG $OFF; }
EV=$(ev)
lvl() { echo "$EV" | awk -v v="$1" -v n="$2" '$1==v && $4==n {print $5}' | sort -u | tr '\n' ' ' | sed 's/ $//'; }
t "log file exists and gets new entries"                "[ -s $LOG ] && [ \$(stat -c %s $LOG) -gt $OFF ]"
t "namespace create  -> RequestResponse"                "[ \"\$(lvl create q10-ns-$R)\" = RequestResponse ]"
t "secret create in web -> Request (body logged)"       "[ \"\$(lvl create q10-sec-$R)\" = Request ]"
t "configmap create (core) -> Request"                  "[ \"\$(lvl create q10-cm-$R)\" = Request ]"
t "role create (rbac, everything else) -> Metadata"     "[ \"\$(lvl create q10-role-$R)\" = Metadata ]"
KPE=$(echo "$EV" | awk '$2=="system:kube-proxy" && ($3=="services" || $3=="endpoints")')
t "system:kube-proxy watch on services/endpoints NOT logged (its list still is)" \
                                                        "! echo \"\$KPE\" | grep -q '^watch ' && echo \"\$KPE\" | grep -q '^list .* services '"

kubectl delete ns q10-ns-$R --wait=false >/dev/null 2>&1
kubectl -n web delete secret q10-sec-$R >/dev/null 2>&1
kubectl -n default delete configmap q10-cm-$R >/dev/null 2>&1
kubectl -n default delete role q10-role-$R >/dev/null 2>&1
rm -rf "$T"

echo
echo "Score: $pass / $total"
