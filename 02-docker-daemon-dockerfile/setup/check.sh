#!/usr/bin/env bash
# Grader. Runs INSIDE the node as root (check.ps1 copies it in, runs it, deletes it).
K="/var/lib/minikube/binaries/$(ls /var/lib/minikube/binaries | sort -V | tail -1)/kubectl --kubeconfig /etc/kubernetes/admin.conf"
Y=/opt/course/02/deployment.yaml
D=$(mktemp); grep -vE '^\s*#' /opt/course/02/Dockerfile > "$D"   # ignore comment lines
trap 'rm -f "$D"' EXIT
pass=0; total=0
ok()  { total=$((total+1)); pass=$((pass+1)); printf '  \e[32m[PASS]\e[0m %s\n' "$1"; }
bad() { total=$((total+1));                   printf '  \e[31m[FAIL]\e[0m %s\n' "$1"; }
t()   { if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi; }

echo "Task A: Docker daemon"
t "developer is NOT in group docker"                    "! id -nG developer | tr ' ' '\n' | grep -qx docker"
t "developer is still in group dev"                     "id -nG developer | tr ' ' '\n' | grep -qx dev"
t "/var/run/docker.sock owned by root:root"             "[ \"\$(stat -L -c %U:%G /var/run/docker.sock)\" = root:root ]"
t "docker.socket unit has SocketGroup=root (persists)"  "[ \"\$(systemctl show docker.socket -p SocketGroup --value)\" = root ]"
t "dockerd is not listening on any TCP port"            "! ss -ltnp | grep -q '\"dockerd\"'"
t "no tcp:// host in docker.service / daemon.json"      "! (systemctl cat docker.service; cat /etc/docker/daemon.json 2>/dev/null) | grep -v '^#' | grep -q 'tcp://'"
t "API server healthy"                                  "curl -skf https://127.0.0.1:8443/readyz"

echo "Task B: Dockerfile (/opt/course/02/Dockerfile)"
t "base image pinned (no :latest / untagged FROM)"      "grep -E '^FROM ' $D | grep -vqE ':latest|^FROM [^:]+\$'"
t "no hard-coded secret in ENV/ARG"                     "! grep -iE '^(ENV|ARG).*(PASS|SECRET|TOKEN|KEY)' $D"
t "no ssh server / sudo installed"                      "! grep -iE 'openssh-server|sudo' $D"
t "no chmod 777"                                        "! grep -E 'chmod +(-R +)?777' $D"
t "no EXPOSE 22"                                        "! grep -E '^EXPOSE.*\\b22\\b' $D"
t "last USER is nobody (not root)"                      "[ \"\$(grep -E '^USER ' $D | tail -1 | awk '{print \$2}')\" = nobody ]"

echo "Task B: Deployment backend in secure-app (live + $Y)"
J="$K -n secure-app get deploy backend -o jsonpath={.spec.template.spec.containers[0].securityContext"
t "runAsUser 65535"                                     "[ \"\$($J.runAsUser})\" = 65535 ]"
t "readOnlyRootFilesystem true"                         "[ \"\$($J.readOnlyRootFilesystem})\" = true ]"
t "privileged false"                                    "[ \"\$($J.privileged})\" = false ]"
t "allowPrivilegeEscalation false"                      "[ \"\$($J.allowPrivilegeEscalation})\" = false ]"
t "manifest file also fixed (65535 / readOnly true / privileged false)" \
  "grep -q 'runAsUser: 65535' $Y && grep -q 'readOnlyRootFilesystem: true' $Y && grep -q 'privileged: false' $Y"
t "backend pod Running and Ready"                       "[ \"\$($K -n secure-app get deploy backend -o jsonpath={.status.readyReplicas})\" = 1 ]"

echo
echo "Score: $pass / $total"
