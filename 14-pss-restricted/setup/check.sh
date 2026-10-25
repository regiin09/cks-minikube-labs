#!/usr/bin/env bash
# Grader. Runs INSIDE the node as root (check.ps1 copies it in, runs it, deletes it).
NS=team-red
DEP=web-server
M=/opt/course/14/deployment.yaml
PY=$(mktemp); LIVE=$(mktemp); FILE=$(mktemp)
trap 'rm -f "$PY" "$LIVE" "$FILE"' EXIT
pass=0; total=0
ok()  { total=$((total+1)); pass=$((pass+1)); printf '  \e[32m[PASS]\e[0m %s\n' "$1"; }
bad() { total=$((total+1));                   printf '  \e[31m[FAIL]\e[0m %s\n' "$1"; }
t()   { if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi; }

# helper: reads a Deployment (or a List holding it) as JSON, checks one rule of the pod template
cat > "$PY" <<'EOF'
import json, sys
rule = sys.argv[1]
d = json.load(sys.stdin)
if d.get("kind") == "List":
    d = [i for i in d["items"] if i.get("kind") == "Deployment" and i["metadata"]["name"] == "web-server"][0]
tpl = d["spec"]["template"]; spec = tpl["spec"]
psc = spec.get("securityContext") or {}
ctrs = spec.get("containers", []) + spec.get("initContainers", []) + spec.get("ephemeralContainers", [])
csc = lambda c: c.get("securityContext") or {}
def eff(c, key):                      # container value wins over pod value
    return csc(c).get(key, psc.get(key))
if rule == "ape":
    ok = all(csc(c).get("allowPrivilegeEscalation") is False for c in ctrs)
elif rule == "drop":
    ok = all("ALL" in ((csc(c).get("capabilities") or {}).get("drop") or []) and
             set((csc(c).get("capabilities") or {}).get("add") or []) <= {"NET_BIND_SERVICE"} for c in ctrs)
elif rule == "nonroot":
    ok = all(eff(c, "runAsNonRoot") is True and eff(c, "runAsUser") != 0 for c in ctrs)
elif rule == "seccomp":
    ok = all((eff(c, "seccompProfile") or {}).get("type") in ("RuntimeDefault", "Localhost") for c in ctrs) and \
         all((csc(c).get("seccompProfile") or {}).get("type") != "Unconfined" for c in ctrs) and \
         (psc.get("seccompProfile") or {}).get("type") != "Unconfined"
elif rule == "priv":
    ok = all(not csc(c).get("privileged") for c in ctrs)
elif rule == "host":
    ok = not any(spec.get(k) for k in ("hostNetwork", "hostPID", "hostIPC")) and \
         not any("hostPath" in v for v in spec.get("volumes") or []) and \
         not any(p.get("hostPort") for c in ctrs for p in c.get("ports") or [])
elif rule == "pod":                   # print the pod template as a Pod for a server-side dry-run
    print(json.dumps({"apiVersion": "v1", "kind": "Pod",
        "metadata": {"name": "q14-grader-dryrun", "namespace": "team-red", "labels": tpl.get("metadata", {}).get("labels", {})},
        "spec": spec})); ok = True
sys.exit(0 if ok else 1)
EOF
R() { python3 "$PY" "$2" < "$1"; }
# admitted by the namespace's PSA (server dry-run) with no PodSecurity warning/error
DRY() { out=$(python3 "$PY" pod < "$1" | kubectl create --dry-run=server -f - 2>&1) && ! echo "$out" | grep -qi 'podsecurity\|violate'; }

kubectl -n $NS get deploy $DEP -o json > "$LIVE" 2>/dev/null
kubectl create --dry-run=client -o json -f $M > "$FILE" 2>/dev/null

echo "Namespace $NS"
t "still enforces restricted (label not removed/changed)" \
  "[ \"\$(kubectl get ns $NS -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}')\" = restricted ]"

echo "Deployment $DEP pod template (live)"
t "allowPrivilegeEscalation: false on every container"    "R $LIVE ape"
t "capabilities drop [\"ALL\"] (no extra adds)"           "R $LIVE drop"
t "runAsNonRoot: true and no runAsUser: 0"                "R $LIVE nonroot"
t "seccompProfile RuntimeDefault/Localhost"               "R $LIVE seccomp"
t "no privileged container"                               "R $LIVE priv"
t "no hostPath / hostNetwork / hostPID / hostIPC / hostPort" "R $LIVE host"
t "server dry-run of the template in $NS: no PodSecurity violation" "DRY $LIVE"

echo "Deployment $DEP (live behaviour)"
t "all replicas updated, ready and available" \
  "S() { kubectl -n $NS get deploy $DEP -o jsonpath=\"{.\$1}\"; }; r=\$(S spec.replicas); [ \"\$r\" -ge 1 ] && [ \"\$(S status.readyReplicas)\" = \$r ] && [ \"\$(S status.updatedReplicas)\" = \$r ] && [ -z \"\$(S status.unavailableReplicas)\" ]"
t "nginx answers on :8080 inside the Pod" \
  "kubectl -n $NS exec deploy/$DEP -- wget -qO- -T 3 http://127.0.0.1:8080 | grep -qi nginx"

echo "Manifest $M"
t "file updated: template passes the restricted PSA dry-run" "[ -s $FILE ] && DRY $FILE && R $FILE ape && R $FILE drop && R $FILE nonroot && R $FILE seccomp"

echo
echo "Score: $pass / $total"
