#!/usr/bin/env bash
# Runs INSIDE a node (as the minikube login user). Checks the shell the way you use it:
# a real terminal, "sudo -i", then kubectl / k / completion / vi.
out=$(printf '%s\n' \
  'echo "KUBECTL=$(command -v kubectl)"' \
  'kubectl get nodes --no-headers >/dev/null 2>&1 && echo KGET=ok' \
  'k get nodes --no-headers >/dev/null 2>&1 && echo KALIAS=ok' \
  'complete -p kubectl >/dev/null 2>&1 && echo COMP_KUBECTL=ok' \
  'complete -p k 2>/dev/null | grep -q __start_kubectl && echo COMP_K=ok' \
  'COMP_WORDS=(k get p); COMP_CWORD=2; COMP_LINE="k get p"; COMP_POINT=7; __start_kubectl k p get 2>/dev/null; printf "%s\n" "${COMPREPLY[@]}" | grep -qx pods && echo COMP_WORKS=ok' \
  '[ "$do" = "--dry-run=client -o yaml" ] && echo DO=ok' \
  'exit' | script -qc 'sudo -i' /dev/null 2>&1)

vimout=$(script -qc "vi -c 'redir! > /tmp/.vchk' -c 'set compatible? backspace?' -c 'redir END' -c 'qa!'" /dev/null >/dev/null 2>&1; cat /tmp/.vchk 2>/dev/null; rm -f /tmp/.vchk)

pass=0; total=0
chk() { total=$((total+1)); if echo "$2" | grep -q "$3"; then pass=$((pass+1)); echo "  [PASS] $1"; else echo "  [FAIL] $1"; fi; }
chk "kubectl on PATH after sudo -i"          "$out"    'KUBECTL=/usr/local/bin/kubectl'
chk "kubectl talks to the cluster"           "$out"    'KGET=ok'
chk "alias k works"                          "$out"    'KALIAS=ok'
chk "completion registered for kubectl"      "$out"    'COMP_KUBECTL=ok'
chk "completion registered for k"            "$out"    'COMP_K=ok'
chk "Tab really completes (k get p -> pods)" "$out"    'COMP_WORKS=ok'
chk "\$do is set"                            "$out"    'DO=ok'
chk "vi is nocompatible (arrows work)"       "$vimout" 'nocompatible'
chk "vi backspace=indent,eol,start"          "$vimout" 'backspace=indent,eol,start'
echo "Node shell: $pass / $total"
