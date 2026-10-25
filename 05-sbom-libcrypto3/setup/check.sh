#!/usr/bin/env bash
# Grader. Runs INSIDE the node as root (check.ps1 copies it in, runs it, deletes it).
BAD=$(base64 -d /var/lib/minikube/.q05)
C=/opt/course/05
M=$C/alpine-deployment.yaml
S=$C/sbom.spdx
pass=0; total=0
ok()  { total=$((total+1)); pass=$((pass+1)); printf '  \e[32m[PASS]\e[0m %s\n' "$1"; }
bad() { total=$((total+1));                   printf '  \e[31m[FAIL]\e[0m %s\n' "$1"; }
t()   { if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi; }
CT() { kubectl -n alpine get deploy alpine -o jsonpath='{range .spec.template.spec.containers[*]}{.name}={.image}{"\n"}{end}'; }

echo "Identify"
t "$C/container.txt names the container with libcrypto3 3.1.4-r5" "[ \"\$(tr -d '[:space:]' < $C/container.txt)\" = $BAD ]"

echo "SBOM ($S)"
t "file exists"                                     "[ -s $S ]"
t "tag-value SPDX format (SPDXVersion: line)"       "grep -qE '^SPDXVersion: SPDX-2' $S"
t "describes alpine:3.19.1"                         "grep -q 'alpine-3.19.1' $S"
t "lists libcrypto3 3.1.4-r5"                       "awk '/^PackageName: /{f=(\$2==\"libcrypto3\")} f' $S | grep -q '^PackageVersion: 3.1.4-r5'"

echo "Deployment alpine (live + $M)"
t "container $BAD removed"                          "! CT | grep -q '^$BAD='"
t "exactly 2 containers left"                       "[ \"\$(CT | grep -c .)\" = 2 ]"
t "no container on alpine:3.19.1"                   "! CT | grep -q 'alpine:3.19.1'"
t "other containers untouched (3.20.0 + 3.21.3)"    "CT | grep -q '=alpine:3.20.0\$' && CT | grep -q '=alpine:3.21.3\$'"
t "rolled out and ready"                            "[ \"\$(kubectl -n alpine get deploy alpine -o jsonpath={.status.readyReplicas})\" = 1 ] && [ \"\$(kubectl -n alpine get deploy alpine -o jsonpath={.status.updatedReplicas})\" = 1 ]"
t "manifest file updated too"                       "! grep -q 'alpine:3.19.1' $M && grep -q 'alpine:3.20.0' $M && grep -q 'alpine:3.21.3' $M"

echo
echo "Score: $pass / $total"
