#!/usr/bin/env bash
# Grader. Runs INSIDE the node as root (check.ps1 copies it in, runs it, deletes it).
# Checks the namespace label, the sidecars on the live Pods, the PeerAuthentication,
# and live traffic: in-mesh client gets through, plaintext client from legacy is refused.
NS=shop
URL=http://web.shop.svc.cluster.local/
pass=0; total=0
ok()  { total=$((total+1)); pass=$((pass+1)); printf '  \e[32m[PASS]\e[0m %s\n' "$1"; }
bad() { total=$((total+1));                   printf '  \e[31m[FAIL]\e[0m %s\n' "$1"; }
t()   { if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi; }
# container names (regular + native sidecars in initContainers) of the pods matching $2 in ns $1
names() { kubectl -n "$1" get pods -l "$2" --field-selector=status.phase=Running \
  -o jsonpath='{range .items[*]}{.metadata.deletionTimestamp}|{.metadata.name}:{range .spec.initContainers[*]}{.name},{end}{range .spec.containers[*]}{.name},{end}{"\n"}{end}' \
  | grep '^|'; }   # skip Pods that are terminating
all_have_proxy() { local l; l=$(names "$1" "$2"); [ -n "$l" ] && ! echo "$l" | grep -qv 'istio-proxy,'; }
none_have_proxy() { local l; l=$(names "$1" "$2"); [ -n "$l" ] && ! echo "$l" | grep -q 'istio-proxy,'; }
PA() { kubectl -n $NS get peerauthentication default -o jsonpath="$1"; }

echo "Sidecar injection (namespace $NS)"
t "namespace $NS labelled istio-injection=enabled"  "[ \"\$(kubectl get ns $NS -o jsonpath='{.metadata.labels.istio-injection}')\" = enabled ]"
t "every Pod of Deployment web has an istio-proxy"  "all_have_proxy $NS app=web"
t "Deployment web Ready (all replicas)"             "[ \"\$(kubectl -n $NS get deploy web -o jsonpath={.status.readyReplicas})\" = \"\$(kubectl -n $NS get deploy web -o jsonpath={.spec.replicas})\" ] && [ \"\$(kubectl -n $NS get deploy web -o jsonpath={.status.updatedReplicas})\" = \"\$(kubectl -n $NS get deploy web -o jsonpath={.spec.replicas})\" ]"

echo "PeerAuthentication"
t "PeerAuthentication 'default' in namespace $NS"   "kubectl -n $NS get peerauthentication default"
t "spec.mtls.mode is STRICT"                        "[ \"\$(PA '{.spec.mtls.mode}')\" = STRICT ]"
t "namespace-wide (no selector)"                    "kubectl -n $NS get peerauthentication default && [ -z \"\$(PA '{.spec.selector}')\" ]"

echo "Live traffic -> $URL"
P=q08-mesh-$RANDOM
kubectl -n $NS run $P --image=curlimages/curl:8.11.1 --restart=Never --labels=q08=probe \
  --command -- sleep 300 >/dev/null 2>&1
kubectl -n $NS wait --for=condition=ready pod/$P --timeout=90s >/dev/null 2>&1
MESH=$(kubectl -n $NS exec $P -c $P -- curl -s -o /dev/null -w '%{http_code}' -m 5 $URL 2>/dev/null)
t "in-mesh client (with sidecar, in $NS) gets HTTP 200" "all_have_proxy $NS q08=probe && [ \"$MESH\" = 200 ]"
kubectl -n $NS delete pod $P --grace-period=0 --force --wait=false >/dev/null 2>&1
PLAIN=$(kubectl -n legacy exec deploy/legacy-client -- curl -s -o /dev/null -w '%{http_code}' -m 5 $URL 2>/dev/null)
t "plaintext client (legacy, no sidecar) is REFUSED" "none_have_proxy legacy app=legacy-client && [ \"$MESH\" = 200 ] && [ \"$PLAIN\" != 200 ]"

echo
echo "Score: $pass / $total"
