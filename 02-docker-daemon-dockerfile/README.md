# Q02 — Secure the Docker daemon + Dockerfile / Deployment best practices

Also covers securing the Docker daemon: remove a user from the `docker` group, and make `/var/run/docker.sock` owned by root.

| | |
|---|---|
| Domain | System Hardening + Supply Chain / Minimize microservice vulnerabilities |
| Node | 1 × minikube `cks-q02` (2 CPU, 2 GB RAM, Docker driver, **docker** runtime) |
| Kubernetes | v1.35.1 |
| Grader | `.\check.ps1`: 19 checks, run after you finish |
| Target time | **Task A 7 min · Task B 6 min** |

> ⚠️ Every `kubectl` command here uses `--context cks-q02`. Never drop it: your kubeconfig may also contain real clusters.

---

## 1. Get ready (setup)

```powershell
cd 02-docker-daemon-dockerfile
.\setup.ps1
```

This takes ~2–3 minutes and ends with `Ready. Start your timer…`. Setup restarts Docker on the node, so give the control plane ~30s, then check:

```powershell
kubectl --context cks-q02 get pods -A
```

The grader confirms the starting state is broken (`2 / 19`):

```powershell
.\check.ps1
```

---

## 2. The tasks (start the timer)

### Task A: Secure the Docker daemon on node `cks-q02` (7 min)

> The Docker daemon on node `cks-q02` is configured insecurely. Perform the following:
>
> 1. Remove user `developer` from the `docker` group. **Do not** remove the user from any other group.
> 2. Reconfigure and restart the Docker daemon so the socket file `/var/run/docker.sock` is owned by user `root` and group `root`.
> 3. Reconfigure and restart the Docker daemon so it does **not** listen on any TCP port (it currently exposes the API unauthenticated on `2375`).
> 4. The changes must survive a restart of Docker. Ensure the Kubernetes cluster is healthy afterwards.
>
> ⚠️ The user named `docker` is minikube's own login user. Leave it alone; the task is about `developer`.

### Task B: Dockerfile and Deployment best practices (6 min)

> Files are on node `cks-q02` in `/opt/course/02/`.
>
> 1. Analyse `/opt/course/02/Dockerfile` and fix **all** the security / best-practice issues (there are 5+). The image must run as user `nobody`. Do not build or push the image.
> 2. Analyse `/opt/course/02/deployment.yaml` and fix the container's `securityContext`:
>    - `runAsUser: 65535`
>    - `readOnlyRootFilesystem: true`
>    - `privileged: false`
>    - `allowPrivilegeEscalation: false`
> 3. Apply the fixed manifest. Deployment `backend` in namespace `secure-app` (already running, insecure) must end up Running with these settings.

---

## 3. Log in to the node

```powershell
minikube -p cks-q02 ssh --native-ssh=false
sudo -i
```

(Exam equivalent: `ssh cks-q02`, `sudo -i`.) On the node, as root, `kubectl` and `k` work with **Tab completion**, plus `$do` (= `--dry-run=client -o yaml`), like the exam:

```bash
k get pods -n secure-app
```

Leave the node with `exit` twice. Then grade yourself:

```powershell
.\check.ps1
```

---

## 4. Answers

<details>
<summary>Click to reveal. Try it first!</summary>

### Task A: Docker daemon

**Look first**

```bash
id developer                                   # groups: developer docker dev
ls -l /var/run/docker.sock                     # root docker
ss -ltnp | grep dockerd                        # *:2375  ← open, no TLS
curl -s http://127.0.0.1:2375/version          # anyone can talk to docker = root on the node
systemctl cat docker.service | grep ExecStart  # where the -H flags live
systemctl cat docker.socket                    # SocketGroup=docker
cat /etc/docker/daemon.json                    # may also hold "hosts" / "group"
```

**1. Remove `developer` from `docker` only**

```bash
gpasswd -d developer docker
id developer        # docker gone, dev still there
```

(`usermod -G dev developer` also works, but you must list every group to keep. `gpasswd -d` is safer.)

**2. Socket owned by `root:root` (two places!)**

```bash
# a) the systemd socket unit
vi /lib/systemd/system/docker.socket
#    SocketGroup=docker   →   SocketGroup=root
```

```bash
# b) dockerd itself. It ALSO has -H unix:///var/run/docker.sock and re-creates the
#    socket using its own --group (default "docker"). Set it in daemon.json:
vi /etc/docker/daemon.json
#    add  "group": "root"   to the JSON object (mind the commas)
```

> 🔑 **This is the trap.** If you only change `SocketGroup`, the socket stays `root:docker`. Whenever dockerd is started with its own `-H unix://...`, set `"group": "root"` in `daemon.json` (or `--group root` in ExecStart). `chgrp root /var/run/docker.sock` is **not** a fix, because it's gone on the next restart.

**3. No TCP listener**

```bash
vi /lib/systemd/system/docker.service
#    delete   -H tcp://0.0.0.0:2375
# also check /etc/docker/daemon.json has no "hosts": ["tcp://..."]
# and that there is no override:  ls /etc/systemd/system/docker.service.d/
```

> Don't put `hosts` in **both** daemon.json and `-H` flags, or dockerd refuses to start.

**4. Restart and verify**

```bash
systemctl daemon-reload
systemctl restart docker.socket docker
ls -l /var/run/docker.sock           # srw-rw---- root root
ss -ltnp | grep dockerd              # nothing
id developer
```

The control plane restarts with Docker. Wait ~30–60s, then `k get pods -A`.

### Task B: Dockerfile

| # | Before | After | Why |
|---|---|---|---|
| 1 | `FROM ubuntu:latest` | `FROM ubuntu:22.04` | pinned, reproducible, scannable |
| 2 | `ENV DB_PASSWORD=SuperSecret123` | *(delete)* | secrets baked into image layers |
| 3 | `apt-get install -y curl wget netcat-openbsd openssh-server sudo` | `apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*` | smaller attack surface, no sshd/sudo/nc |
| 4 | `chmod 777` | `chmod 755` | no world-writable binaries |
| 5 | `EXPOSE 22` | *(delete)* | no ssh in a container |
| 6 | `USER root` | `USER nobody` | never run as root |

Full file: [`solution/Dockerfile`](solution/Dockerfile).

### Task B: Deployment

```bash
vi /opt/course/02/deployment.yaml
```

```yaml
        securityContext:
          runAsUser: 65535
          privileged: false
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
```

```bash
k apply -f /opt/course/02/deployment.yaml
k -n secure-app rollout status deploy/backend
k -n secure-app logs deploy/backend        # "running as 65535"
```

Full file: [`solution/deployment.yaml`](solution/deployment.yaml).

> `readOnlyRootFilesystem: true` breaks apps that write to `/tmp`, `/var/cache`, etc. On the exam, if the pod crashes after this, add an `emptyDir` volume mounted at the path it writes to. Don't turn readOnly back off.

</details>

---

## 5. Retry from scratch

`.\cleanup.ps1` then `.\setup.ps1` (~3 min).

## 6. Delete the node (before the next question)

```powershell
.\cleanup.ps1
```

or `minikube delete -p cks-q02`. Setup uses `--keep-context`, so your current kubectl context is never switched. Always pass `--context cks-q02`.

---

## Files

```
02-docker-daemon-dockerfile/
  README.md
  setup.ps1                 start node, break dockerd, drop task files, apply insecure Deployment
  check.ps1                 grader (19 checks)
  cleanup.ps1               delete node
  setup/break-node.sh       runs on node: developer→docker group, dockerd on :2375 no TLS
  setup/check.sh            grader logic (runs on node)
  setup/Dockerfile          insecure Dockerfile (→ /opt/course/02/)
  setup/app.sh              tiny app copied by the Dockerfile
  yaml/deployment.yaml      insecure Deployment (→ /opt/course/02/ and applied)
  solution/Dockerfile       fixed
  solution/deployment.yaml  fixed
```

Refs: [Protect the Docker daemon socket](https://docs.docker.com/engine/security/protect-access/) · [dockerd reference (`--group`, `-H`, daemon.json)](https://docs.docker.com/reference/cli/dockerd/) · [Dockerfile best practices](https://docs.docker.com/build/building/best-practices/) · [Pod securityContext](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)
