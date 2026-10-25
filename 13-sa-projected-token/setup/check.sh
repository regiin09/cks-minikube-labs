#!/usr/bin/env bash
# Grader. Runs INSIDE the node as root (check.ps1 copies it in, runs it, deletes it).
NS=monitoring; SA=stats-monitor-sa; D=stats-monitor
M=/opt/course/13/deployment.yaml
TP=/var/run/secrets/kubernetes.io/serviceaccount/token
pass=0; total=0
ok()  { total=$((total+1)); pass=$((pass+1)); printf '  \e[32m[PASS]\e[0m %s\n' "$1"; }
bad() { total=$((total+1));                   printf '  \e[31m[FAIL]\e[0m %s\n' "$1"; }
t()   { if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi; }

# Reads a Deployment (JSON) on stdin, prints one flag per satisfied item.
SPEC() { python3 -c '
import sys, json, posixpath
try: d = json.load(sys.stdin)
except Exception: sys.exit(0)
if d.get("kind") == "List": d = next((i for i in d["items"] if i.get("kind") == "Deployment"), {})
s = d.get("spec", {}).get("template", {}).get("spec", {})
TP = "/var/run/secrets/kubernetes.io/serviceaccount/token"
if s.get("serviceAccountName") == "stats-monitor-sa": print("SA")
if s.get("automountServiceAccountToken") is not True: print("NOPODAUTO")
v = next((v for v in s.get("volumes", []) if v.get("name") == "token"), None)
if v is None: sys.exit(0)
src = [x["serviceAccountToken"] for x in v.get("projected", {}).get("sources", []) if "serviceAccountToken" in x]
if not src: sys.exit(0)
print("PROJ"); st = src[0]
if st.get("expirationSeconds") == 3600: print("EXP")
c = (s.get("containers") or [{}])[0]
m = next((m for m in c.get("volumeMounts", []) if m.get("name") == "token"), None)
if m is None: sys.exit(0)
mp = m.get("mountPath", "").rstrip("/"); sp = m.get("subPath", "")
# dir mount: mountPath + projected path | file mount: mountPath is the file, subPath = projected path
full = (mp if sp == st.get("path") else "") if sp else posixpath.join(mp, st.get("path", ""))
if full == TP: print("PATH")
if m.get("readOnly") is True: print("RO")
'; }
LIVE=$(kubectl -n $NS get deploy $D -o json 2>/dev/null | SPEC)
FILE=$(kubectl create --dry-run=client -o json -f $M 2>/dev/null | SPEC)
has() { echo "$1" | grep -qx "$2"; }

echo "ServiceAccount $SA (live)"
t "automountServiceAccountToken: false"                  "[ \"\$(kubectl -n $NS get sa $SA -o jsonpath={.automountServiceAccountToken})\" = false ]"

echo "Deployment $D (live)"
t "still uses serviceAccountName $SA"                    "has \"\$LIVE\" SA"
t "Pod spec does not override automount back to true"    "has \"\$LIVE\" NOPODAUTO"
t "volume 'token' is projected with serviceAccountToken" "has \"\$LIVE\" PROJ"
t "serviceAccountToken expirationSeconds: 3600"          "has \"\$LIVE\" EXP"
t "token file lands at $TP"                              "has \"\$LIVE\" PATH"
t "volumeMount 'token' has readOnly: true"               "has \"\$LIVE\" RO"

echo "Running Pod (live)"
PODS=$(kubectl -n $NS get pod -l app=$D -o json)
t "rolled out: 1 ready, 1 updated replica"               "[ \"\$(kubectl -n $NS get deploy $D -o jsonpath={.status.readyReplicas})\" = 1 ] && [ \"\$(kubectl -n $NS get deploy $D -o jsonpath={.status.updatedReplicas})\" = 1 ]"
NOAUTO=0
echo "$PODS" | python3 -c '
import sys, json
p = [i for i in json.load(sys.stdin)["items"] if not i["metadata"].get("deletionTimestamp")]
assert p
for i in p:
    assert not any(v["name"].startswith("kube-api-access-") for v in i["spec"].get("volumes", [])), i["metadata"]["name"]
' >/dev/null 2>&1 && NOAUTO=1
t "no running Pod has an auto-injected kube-api-access-* volume" "[ $NOAUTO = 1 ]"
POD=$(echo "$PODS" | python3 -c '
import sys, json
print(next(i["metadata"]["name"] for i in json.load(sys.stdin)["items"]
           if not i["metadata"].get("deletionTimestamp") and i["status"].get("phase") == "Running"))' 2>/dev/null)
TOK=""; [ $NOAUTO = 1 ] && [ -n "$POD" ] && TOK=$(kubectl -n $NS exec "$POD" -- cat $TP 2>/dev/null)
t "token file exists in the container (from your volume)" "[ -n \"\$TOK\" ]"
WHO=""
if [ -n "$TOK" ]; then
  WHO=$(curl -sk -X POST -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' \
        -d '{"apiVersion":"authentication.k8s.io/v1","kind":"SelfSubjectReview"}' \
        https://127.0.0.1:8443/apis/authentication.k8s.io/v1/selfsubjectreviews \
        | python3 -c 'import sys,json; print(json.load(sys.stdin)["status"]["userInfo"]["username"])' 2>/dev/null)
fi
t "token authenticates as system:serviceaccount:$NS:$SA" "[ \"\$WHO\" = system:serviceaccount:$NS:$SA ]"
LIFE=$(echo "$TOK" | python3 -c '
import sys, json, base64
p = sys.stdin.read().strip().split(".")[1]; p += "=" * (-len(p) % 4)
j = json.loads(base64.urlsafe_b64decode(p)); print(j["exp"] - j["iat"])' 2>/dev/null)
t "token lifetime is 3600s (bound, expiring token)"      "[ \"\$LIFE\" = 3600 ]"

echo "Manifest file ($M)"
t "file has the projected volume + expirationSeconds 3600" "has \"\$FILE\" PROJ && has \"\$FILE\" EXP"
t "file mounts it at the token path, readOnly"           "has \"\$FILE\" PATH && has \"\$FILE\" RO"

echo
echo "Score: $pass / $total"
