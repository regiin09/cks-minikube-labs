#!/usr/bin/env bash
# Grader. Runs INSIDE the node as root (check.ps1 copies it in, runs it, deletes it).
K="/var/lib/minikube/binaries/$(ls /var/lib/minikube/binaries | sort -V | tail -1)/kubectl --kubeconfig /etc/kubernetes/admin.conf"
BAD=$(base64 -d /var/lib/minikube/.q03)
L=/etc/falco/falco_rules.local.yaml
C=/opt/course/03
FMT='%evt.time,%container.id,%k8s.ns.name,%k8s.pod.name,%proc.name'
pass=0; total=0
ok()  { total=$((total+1)); pass=$((pass+1)); printf '  \e[32m[PASS]\e[0m %s\n' "$1"; }
bad() { total=$((total+1));                   printf '  \e[31m[FAIL]\e[0m %s\n' "$1"; }
t()   { if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi; }
# the rule block: from its "- rule:" line up to the next top-level "- " item
RULE=$(awk '/^- rule: *Pod accessing \/dev\/mem *$/{f=1;print;next} f&&/^- /{f=0} f' "$L")

echo "Falco rule ($L)"
t "rule 'Pod accessing /dev/mem' exists"                 "[ -n \"\$RULE\" ]"
t "condition matches /dev/mem"                           "echo \"\$RULE\" | grep -E '^ *condition:' -A3 | grep -q '/dev/mem'"
t "condition limited to containers"                      "echo \"\$RULE\" | grep -E '^ *condition:' -A3 | grep -qE 'container\\.id *!= *host|(^| |\\()container( |\\)|\$)'"
t "output is exactly $FMT"                               "echo \"\$RULE\" | grep -E '^ *output:' | grep -qF \"$FMT\""
t "priority WARNING"                                     "echo \"\$RULE\" | grep -qiE '^ *priority: *warning'"
t "rules load without errors"                            "falco -c /etc/falco/falco.yaml -V /etc/falco/falco_rules.yaml -V $L"

echo "Falco config (/etc/falco/falco.yaml)"
t "minimum priority lets WARNING through"                "grep -qE '^priority: *(debug|informational|info|notice|warning)\\b' /etc/falco/falco.yaml"
t "file_output enabled -> $C/falco.log"                  "sed -n '/^file_output:/,/^[a-z_]*:/p' /etc/falco/falco.yaml | grep -qE '^ +enabled: *true' && sed -n '/^file_output:/,/^[a-z_]*:/p' /etc/falco/falco.yaml | grep -qE \"^ +filename: *['\\\"]?$C/falco.log\""
t "falco service running"                                "systemctl is-active falco-modern-bpf || systemctl is-active falco"
t "$C/falco.log has an alert for the bad pod"            "grep -qE ',ai,$BAD-[a-z0-9]+-[a-z0-9]+,' $C/falco.log"

echo "Response"
t "$C/pod.txt = ai/<bad pod name>"                       "grep -qxE 'ai/$BAD-[a-z0-9]+-[a-z0-9]+' $C/pod.txt"
t "bad Deployment scaled to 0 (not deleted)"             "[ \"\$($K -n ai get deploy $BAD -o jsonpath={.spec.replicas})\" = 0 ]"
for d in nvidia cpu ollama; do
  [ "$d" = "$BAD" ] && continue
  t "Deployment $d untouched (1 replica, ready)"         "[ \"\$($K -n ai get deploy $d -o jsonpath={.status.readyReplicas})\" = 1 ]"
done

echo
echo "Score: $pass / $total"
