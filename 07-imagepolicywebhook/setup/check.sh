#!/usr/bin/env bash
# Grader. Runs INSIDE the node as root (check.ps1 copies it in, runs it, deletes it).
# Checks the config files, the apiserver manifest, and live admission behaviour
# (incl. implicit deny while the scanner is stopped).
EP=/etc/kubernetes/epconfig
M=/etc/kubernetes/manifests/kube-apiserver.yaml
pass=0; total=0
ok()  { total=$((total+1)); pass=$((pass+1)); printf '  \e[32m[PASS]\e[0m %s\n' "$1"; }
bad() { total=$((total+1));                   printf '  \e[31m[FAIL]\e[0m %s\n' "$1"; }
t()   { if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi; }
# admission result for a fresh (never cached) image: prints server response
try() { kubectl run "q07-$RANDOM" --image="$1" --restart=Never --dry-run=server -o name 2>&1; }
R=$RANDOM

echo "Configuration ($EP)"
t "defaultAllow is false (implicit deny)"           "python3 -c \"import json,sys; c=json.load(open('$EP/admission_configuration.json')); sys.exit(0 if c['plugins'][0]['configuration']['imagePolicy']['defaultAllow'] is False else 1)\""
t "kubeconfig server = https://image-scanner.local:8081/image_policy" \
                                                    "grep -qE '^ +server: *https://image-scanner.local:8081/image_policy *\$' $EP/kubeconfig.yaml"

echo "kube-apiserver ($M)"
t "ImagePolicyWebhook in --enable-admission-plugins" "grep -E -- '--enable-admission-plugins=' $M | grep -q ImagePolicyWebhook"
t "--admission-control-config-file set"             "grep -qE -- '--admission-control-config-file=$EP/admission_configuration.json' $M"
t "epconfig mounted into the pod (hostPath)"        "grep -A3 'hostPath:' $M | grep -qE 'path: (/etc/kubernetes/epconfig|/etc/kubernetes)/?\$'"
t "API server healthy"                              "kubectl get --raw /readyz"

echo "Live admission"
t "pinned image allowed"                            "try busybox:1.$R.0 | grep -q '^pod/'"
t ":latest image denied by the scanner"             "try nginx-$R:latest | grep -q 'image scanner rejected'"
systemctl stop image-scanner
t "scanner DOWN -> pinned image denied (implicit)"  "try busybox:2.$R.0 | grep -qi 'forbidden'"
systemctl start image-scanner; sleep 2
t "vulnerable-resource deployed, its Pods rejected" "kubectl get deploy vulnerable && [ -z \"\$(kubectl get deploy vulnerable -o jsonpath={.status.availableReplicas})\" ] && kubectl get events --field-selector reason=FailedCreate -o jsonpath='{.items[*].message}' | grep -q 'image policy webhook'"

echo
echo "Score: $pass / $total"
