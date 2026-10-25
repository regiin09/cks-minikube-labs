# Q15 — kube-apiserver: no anonymous access, Node,RBAC, NodeRestriction

Practice scenario: lock down a kube-apiserver that allows unauthenticated and unauthorized access, and remove a ClusterRoleBinding that gives `system:anonymous` cluster-admin.

| | |
|---|---|
| Domain | Cluster Setup / Cluster Hardening (API server authn, authz, admission) |
| Node | 1 × minikube `cks-q15` (2 CPU, 2 GB RAM), Kubernetes v1.35.1 |
| Manifest | `/etc/kubernetes/manifests/kube-apiserver.yaml` (API server listens on **8443** on minikube, 6443 on the exam) |
| Kubelet credentials | `/etc/kubernetes/kubelet.conf` (user `system:node:cks-q15`), used by the grader to test NodeRestriction |
| Grader | `.\check.ps1`: 16 checks (manifest, **running** flags, pod Ready, live anonymous curl, CRB, live kubelet-credential tests) |
| Target time | **8 minutes** |

> ⚠️ Your kubeconfig may also contain real clusters. From Windows always use `--context cks-q15`.

---

## 1. Get ready (setup)

```powershell
cd 15-apiserver-auth
.\setup.ps1
```

Takes ~3 minutes. Ends with `>> done. Node is ready for the question.` and `Ready…`. Grader start: `5 / 16`.

---

## 2. The task (start the timer)

> The kube-apiserver on control-plane node `cks-q15` has been left wide open: it accepts **anonymous requests** and **authorizes everything**.
>
> Harden it:
> - anonymous users must not be able to use the API
> - authorization mode must be **`Node,RBAC`**
> - the **`NodeRestriction`** admission plugin must be enabled
>
> Also delete the ClusterRoleBinding **`system:anonymous`**, which gives anonymous users cluster-admin.
>
> The kube-apiserver must be running and healthy when you finish. `kubectl` on the node uses the admin kubeconfig (`/root/.kube/config`).

---

## 3. Log in

```powershell
minikube -p cks-q15 ssh --native-ssh=false
sudo -i
```

---

## 4. Answers

<details>
<summary>Click to reveal. Try it first!</summary>

### What setup did (and what it really does on v1.35)

```yaml
    - --anonymous-auth=true
    - --authorization-mode=AlwaysAllow
    - --disable-admission-plugins=NodeRestriction     # only in some runs (random)
    - --enable-admission-plugins=...                  # NodeRestriction removed
```

Verified on this node: with `AlwaysAllow` the API server **ignores** `--anonymous-auth=true` and logs
`AnonymousAuth is not allowed with the AlwaysAllow authorizer. Resetting AnonymousAuth to false`.
So even the "open" starting state answers anonymous curls with 401, its own probes fail, and the pod sits at **0/1**, restarting every ~4 min. That's why the grader's anonymous-curl check already passes at the start.

### Why `--anonymous-auth=false` alone isn't enough (verified, not guessed)

The kubeadm/minikube API server pod has **HTTPS httpGet probes with no credentials**: startup and liveness hit `/livez`, readiness hits `/readyz`. Those endpoints are only readable by anonymous users because of the default binding **`system:public-info-viewer`** (`system:unauthenticated` → `/livez`, `/readyz`, `/healthz`, `/version`). RBAC can only help a request that's already authenticated. With `--anonymous-auth=false` the request is rejected at **authentication** (401) before RBAC is checked, so that binding is no use.

What I saw on v1.35.1 with `--anonymous-auth=false`, `Node,RBAC` and NodeRestriction:
- `curl -k https://<node>:8443/livez` → **401**, and the same for `/readyz` and `/api/v1/namespaces`
- event `Startup probe failed: HTTP probe failed with statuscode: 401`
- pod **0/1**. After 24 × 10 s the kubelet logs `failed startup probe, will be restarted` and the container exits with 137. That repeats every ~4 min, with a growing back-off.
- in between, `kubectl` still works because it authenticates with a cert. That's why it *looks* fine for a few minutes.

### The stable fix: anonymous only for the health endpoints

Kubernetes ≥ 1.32 lets you allow anonymous requests **only for specific paths**, using an `AuthenticationConfiguration` file (`--authentication-config`). This is the documented way to keep health checks working while disabling anonymous access to everything else.

> It is **mutually exclusive** with the flag. If you set both, the API server won't start:
> `--anonymous-auth flag cannot be set when anonymous field is configured in authentication configuration file` (verified).

#### Step 1: the config file (outside `manifests/`)

```bash
mkdir -p /etc/kubernetes/authn
vi /etc/kubernetes/authn/authn-config.yaml
```

```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: AuthenticationConfiguration
anonymous:
  enabled: true
  conditions:          # anonymous ONLY for these paths. Everything else -> 401
  - path: /livez
  - path: /readyz
  - path: /healthz
```

(Copy: [`solution/authn-config.yaml`](solution/authn-config.yaml).)

#### Step 2: the manifest

```bash
cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/kube-apiserver.yaml.bak   # backup OUTSIDE manifests/
vi /etc/kubernetes/manifests/kube-apiserver.yaml
```

```yaml
    - --authentication-config=/etc/kubernetes/authn/authn-config.yaml   # REPLACES --anonymous-auth=true (delete that line)
    - --authorization-mode=Node,RBAC                                     # was AlwaysAllow
    - --enable-admission-plugins=NamespaceLifecycle,...,ResourceQuota,NodeRestriction   # append
    # and DELETE  - --disable-admission-plugins=NodeRestriction   if it's there
...
    volumeMounts:
    - mountPath: /etc/kubernetes/authn
      name: authn-config
      readOnly: true
...
  volumes:
  - hostPath:
      path: /etc/kubernetes/authn
      type: DirectoryOrCreate
    name: authn-config
```

#### Step 3: wait, then verify the running process

```bash
watch "docker ps | grep kube-apiserver"         # exam: watch crictl ps
ps -ef | grep kube-apiserver | tr ' ' '\n' | grep -E 'anonymous|authentication-config|authorization-mode|admission-plugins'
k -n kube-system get pod -l component=kube-apiserver   # must become 1/1 and stay there
```

#### Step 4: clean up the binding

```bash
k get clusterrolebinding system:anonymous -o wide       # -> cluster-admin, User system:anonymous
k delete clusterrolebinding system:anonymous
```

Delete **only** that one. `system:public-info-viewer`, `system:basic-user` and `system:discovery` are defaults. Leave them alone (the health probes rely on `system:public-info-viewer`).

#### Step 5: test

```bash
curl -k https://localhost:8443/api/v1/namespaces    # 401 Unauthorized   (exam: port 6443)
curl -k https://localhost:8443/livez                # ok                 (anonymous allowed only here)

# Node authorizer + NodeRestriction, using the kubelet's own credentials
k --kubeconfig /etc/kubernetes/kubelet.conf get secrets -A
#   Forbidden ... User "system:node:cks-q15" cannot list resource "secrets"
k --kubeconfig /etc/kubernetes/kubelet.conf label node cks-q15 node-restriction.kubernetes.io/x=y
#   Forbidden ... is not allowed to modify labels: node-restriction.kubernetes.io/x
k --kubeconfig /etc/kubernetes/kubelet.conf label node cks-q15 foo=bar --dry-run=server
#   labeled (server dry run). A node CAN still label ITSELF with normal labels
```

### What to do on the exam

The wording is "forbid anonymous authentication". The well-known answer is `--anonymous-auth=false`, and the exam's grader most likely just checks for that flag. I can't verify what it checks. Here's what I verified on a kubeadm-style v1.35 API server: the flag alone leaves the pod 0/1, killed every ~4 min. Pick by time:
1. **Fast:** `--anonymous-auth=false` + `Node,RBAC` + `NodeRestriction` + delete the CRB. kubectl keeps working between restarts. This grader **fails** the "pod Ready" check, on purpose.
2. **Stable (this lab's full marks):** the `AuthenticationConfiguration` above instead of the flag.
3. **Also accepted here:** keep `--anonymous-auth=false` and change the three probes from `httpGet` to `tcpSocket: {port: probe-port}`. Verified 1/1 and stable, but weaker: it only checks that the port is open.

### Traps

| Trap | What happens |
|---|---|
| `--authorization-mode=RBAC,Node` or `Node, RBAC` | Wrong order / a space breaks it. Write exactly **`Node,RBAC`** (Node first, comma, no space) |
| `--authorization-mode=RBAC` (no Node) | Kubelets lose the Node authorizer. The grader fails `Node,RBAC` and NodeRestriction behaviour |
| `--authorization-mode=Webhook` on the **apiserver** | **Never.** Webhook on the apiserver needs `--authorization-webhook-config-file` and won't start without it. `Webhook` belongs to the **kubelet** (Q01) |
| Mixing it up with Q01 (kubelet) | **kubelet**: `/var/lib/kubelet/config.yaml` → `authentication.anonymous.enabled: false`, `authorization.mode: Webhook`, then `systemctl restart kubelet`. **apiserver**: static pod flags → `--anonymous-auth=false` (or authn config), `--authorization-mode=Node,RBAC`, restarts by itself |
| `--anonymous-auth=false` **and** `--authentication-config` with `anonymous:` | API server won't start (mutually exclusive) |
| NodeRestriction appended but `--disable-admission-plugins=NodeRestriction` still there | API server **won't start**: `[NodeRestriction] in enable-admission-plugins and disable-admission-plugins overlapped` (verified). Delete the disable line |
| Trusting the manifest | Check the **running** process: `ps -ef \| grep kube-apiserver`. If your edit is invalid, the old container keeps running |
| Backup **inside** `manifests/` | The kubelet runs every file there. Back up to `/root/` |
| Volume name `authn_config` | Must be RFC 1123 (`a-z0-9-`). The kubelet rejects the manifest: `journalctl -u kubelet \| grep "Could not process manifest"` |
| Config file not mounted | API server crashes: `open /etc/kubernetes/authn/authn-config.yaml: no such file or directory` |
| Deleting `system:public-info-viewer` "because it's anonymous" | The health endpoints then 401 for anonymous users too, and the probes fail again |
| API server down, nothing works | `docker ps -a \| grep apiserver` (exam: `crictl ps -a`), `docker logs <id>`, or `/var/log/pods/kube-system_kube-apiserver-*/` |

Scripted version: [`solution/solve.sh`](solution/solve.sh) (`solve.sh flag` = the flag-only answer, which the grader fails on "pod Ready").

</details>

---

## 5. Retry from scratch

`.\cleanup.ps1` then `.\setup.ps1`.

## 6. Delete the node (before the next question)

```powershell
.\cleanup.ps1
```

---

## Files

```
15-apiserver-auth/
  README.md
  setup.ps1                         node + break the apiserver + CRB
  check.ps1                         grader (16 checks)
  cleanup.ps1                       delete node
  setup/break-node.sh               anonymous-auth=true, AlwaysAllow, NodeRestriction off (random variant)
  setup/check.sh                    grader logic
  yaml/crb-system-anonymous.yaml    the ClusterRoleBinding to remove
  solution/authn-config.yaml        AuthenticationConfiguration (anonymous only for health paths)
  solution/solve.sh                 scripted solution ("flag" arg = flag-only variant)
```

Refs: [Anonymous authenticator configuration](https://kubernetes.io/docs/reference/access-authn-authz/authentication/#anonymous-authenticator-configuration) · [Node authorization](https://kubernetes.io/docs/reference/access-authn-authz/node/) · [NodeRestriction](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/#noderestriction) · [kube-apiserver flags](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-apiserver/)
