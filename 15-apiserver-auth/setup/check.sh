#!/usr/bin/env bash
# Grader. Runs INSIDE the node as root (check.ps1 copies it in, runs it, deletes it).
# Checks the manifest, the RUNNING kube-apiserver flags, live anonymous access, live
# Node authorizer + NodeRestriction behaviour (with the kubelet's own credentials),
# the ClusterRoleBinding, and that the apiserver is healthy and its probes pass.
M=/etc/kubernetes/manifests/kube-apiserver.yaml
KUBELET="kubectl --kubeconfig /etc/kubernetes/kubelet.conf"
NODE=$(hostname)
pass=0; total=0
ok()  { total=$((total+1)); pass=$((pass+1)); printf '  \e[32m[PASS]\e[0m %s\n' "$1"; }
bad() { total=$((total+1));                   printf '  \e[31m[FAIL]\e[0m %s\n' "$1"; }
t()   { if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi; }
R=$RANDOM

echo "(waiting up to 3 min for the API server to answer...)"
for i in $(seq 1 90); do kubectl get --raw /readyz >/dev/null 2>&1 && break; sleep 2; done
# kube-apiserver pod Ready (= readiness probe passes); give the kubelet up to 60s to notice
for i in $(seq 1 30); do
  [ "$(kubectl -n kube-system get pod kube-apiserver-$NODE -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)" = true ] && break
  sleep 2
done

MAN=$(grep -E -- '^ +- --' $M | sed 's/^ *- //' | tr '\n' ' ')
RUN=$(ps -eo args | grep '^kube-apiserver ' | head -n1)
# anonymous off: --anonymous-auth=false, OR an AuthenticationConfiguration file (the two are
# mutually exclusive). The live 401 test below proves what it really does.
anon_off() { echo " $1 " | grep -q -- ' --anonymous-auth=false ' || \
             { echo " $1 " | grep -q -- ' --authentication-config=' && ! echo " $1 " | grep -q -- ' --anonymous-auth='; }; }
authz()    { echo " $1 " | grep -q -- ' --authorization-mode=Node,RBAC '; }
noderes()  { echo " $1 " | grep -oE -- ' --enable-admission-plugins=[^ ]+' | grep -qE '[=,]NodeRestriction(,|$)' && \
             ! echo " $1 " | grep -oE -- ' --disable-admission-plugins=[^ ]+' | grep -q NodeRestriction; }

echo "Manifest ($M)"
t "anonymous authentication disabled"                "anon_off \"\$MAN\""
t "--authorization-mode=Node,RBAC (exactly)"         "authz \"\$MAN\""
t "NodeRestriction enabled (and not disabled)"       "noderes \"\$MAN\""

echo "Running kube-apiserver process (ps)"
t "anonymous authentication disabled"                "anon_off \"\$RUN\""
t "--authorization-mode=Node,RBAC"                   "authz \"\$RUN\""
t "NodeRestriction enabled"                          "noderes \"\$RUN\""

echo "Health"
t "admin kubectl works (can-i '*' '*')"              "kubectl auth can-i '*' '*' | grep -qx yes"
t "kube-apiserver pod Ready 1/1 (probes pass)"       "[ \"\$(kubectl -n kube-system get pod kube-apiserver-$NODE -o jsonpath='{.status.containerStatuses[0].ready}')\" = true ]"
t "kube-apiserver not restarting (restartCount 0)"   "[ \"\$(kubectl -n kube-system get pod kube-apiserver-$NODE -o jsonpath='{.status.containerStatuses[0].restartCount}')\" = 0 ]"
t "no stray files in /etc/kubernetes/manifests"      "[ -z \"\$(ls -A /etc/kubernetes/manifests | grep -vE '^(etcd|kube-apiserver|kube-controller-manager|kube-scheduler)\.yaml\$')\" ]"

echo "Live: anonymous + RBAC"
t "anonymous GET /api/v1/namespaces -> 401/403"      "curl -sk -o /dev/null -w '%{http_code}' https://127.0.0.1:8443/api/v1/namespaces | grep -qE '^40[13]\$'"
t "ClusterRoleBinding system:anonymous deleted"      "! kubectl get clusterrolebinding system:anonymous"
t "default CRB system:public-info-viewer kept"       "kubectl get clusterrolebinding system:public-info-viewer"

echo "Live: kubelet credentials (/etc/kubernetes/kubelet.conf)"
t "kubelet creds can NOT list secrets (no AlwaysAllow)" "$KUBELET get secrets -n kube-system 2>&1 | grep -q Forbidden"
t "NodeRestriction blocks node-restriction.kubernetes.io/ label" \
                                                     "$KUBELET label node $NODE node-restriction.kubernetes.io/q15-$R=x --dry-run=server 2>&1 | grep -q 'not allowed to modify labels'"
kubectl create -f - >/dev/null 2>&1 <<EON
apiVersion: v1
kind: Node
metadata:
  name: q15-other-node
EON
# raw PATCH: "kubectl label" does a GET first, and the v1.35 Node authorizer already blocks
# a node from reading other Nodes, so kubectl would never reach admission.
KCERT=/var/lib/kubelet/pki/kubelet-client-current.pem
patch_other() { curl -sk --cert $KCERT --key $KCERT -X PATCH -H 'Content-Type: application/merge-patch+json' \
  -d "{\"metadata\":{\"labels\":{\"q15\":\"$R\"}}}" 'https://127.0.0.1:8443/api/v1/nodes/q15-other-node?dryRun=All'; }
t "NodeRestriction blocks kubelet editing another Node" "patch_other | grep -q 'not allowed to modify node'"
kubectl delete node q15-other-node --wait=false >/dev/null 2>&1

echo
echo "Score: $pass / $total"
