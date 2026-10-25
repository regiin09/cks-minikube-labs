#!/usr/bin/env bash
# Runs INSIDE the minikube node (as root). Makes the Docker daemon insecure,
# adds user "developer" to the docker group, and drops the Dockerfile task files.
set -euo pipefail

DOCKER_SVC=/lib/systemd/system/docker.service
COURSE=/opt/course/02

echo ">> vi: arrow keys + backspace (vim.tiny defaults to 'compatible')"
grep -q nocompatible /etc/vim/vimrc.tiny || printf 'set nocompatible\nset backspace=indent,eol,start\n' >> /etc/vim/vimrc.tiny

echo ">> user developer: in groups docker + dev"
getent group dev >/dev/null || groupadd dev
id developer >/dev/null 2>&1 || useradd -m -s /bin/bash developer
usermod -aG docker,dev developer

echo ">> dockerd: unauthenticated TCP API on 2375 (no TLS)"
cp -n "$DOCKER_SVC" /root/docker.service.orig
# swap minikube's TLS port 2376 for plain 2375 and strip the TLS flags
sed -i -e 's|-H tcp://0.0.0.0:2376|-H tcp://0.0.0.0:2375|' \
       -e 's|\s*--tlsverify||' \
       -e 's|\s*--tlscacert [^ \t]*||' \
       -e 's|\s*--tlscert [^ \t]*||' \
       -e 's|\s*--tlskey [^ \t]*||' "$DOCKER_SVC"
systemctl daemon-reload
systemctl restart docker.socket docker

echo ">> Dockerfile task files in $COURSE"
mkdir -p "$COURSE"
cp /tmp/q02/Dockerfile /tmp/q02/app.sh /tmp/q02/deployment.yaml "$COURSE/"
docker pull -q busybox:1.36 >/dev/null

echo ">> waiting for the API server to come back after the docker restart"
for i in $(seq 1 90); do
  if curl -sk https://127.0.0.1:8443/readyz >/dev/null 2>&1; then break; fi
  sleep 2
done
curl -s http://127.0.0.1:2375/version >/dev/null && echo ">> confirmed: docker API open on :2375 without auth"

echo ">> done. Node is ready for the question."
