# Q07 — ImagePolicyWebhook: finish the config, implicit deny

Practice scenario: finish an incomplete ImagePolicyWebhook setup in `/etc/kubernetes/epconfig`, point it at an HTTPS image scanner, and make it fail closed.

| | |
|---|---|
| Domain | Supply Chain Security / Cluster Setup (admission control) |
| Node | 1 × minikube `cks-q07` (2 CPU, 2 GB RAM) |
| Image scanner | systemd service **`image-scanner`** on the node, HTTPS **`https://image-scanner.local:8081/image_policy`**. Rejects `:latest` and untagged images. Log: **`/var/log/imagepolicy/scanner.log`** |
| Config dir | `/etc/kubernetes/epconfig/`: `admission_configuration.json`, `kubeconfig.yaml`, `scanner-ca.crt`, `apiserver-client.crt/.key` |
| Test resource | `/root/q07/vulnerable-resource.yml` (Deployment using `nginx:latest`) |
| Grader | `.\check.ps1`: 10 checks, incl. **stopping the scanner** to prove implicit deny |
| Target time | **10 minutes** |

---

## 1. Get ready (setup)

```powershell
cd 07-imagepolicywebhook
.\setup.ps1
```

This takes ~2 minutes and ends with `>> scanner is up and rejecting :latest` and `Ready…`. Grader start: `2 / 10`.

---

## 2. The task (start the timer)

> Node `cks-q07` runs an image scanner service at **`https://image-scanner.local:8081/image_policy`**. It rejects images tagged `:latest` or not tagged at all. The cluster doesn't use it yet.
>
> On the control-plane node `cks-q07`, wire the scanner into the API server using the half-finished files in **`/etc/kubernetes/epconfig`**:
>
> 1. Turn on the **ImagePolicyWebhook** admission plugin and give the API server its admission configuration.
> 2. Make the policy **fail closed**: if the scanner can't be reached, Pods must be rejected.
> 3. Point the webhook kubeconfig at the scanner's HTTPS endpoint.
>
> Then apply **`/root/q07/vulnerable-resource.yml`** and confirm that its Pods are refused. The scanner logs every decision to `/var/log/imagepolicy/scanner.log`.

---

## 3. Log in

```powershell
minikube -p cks-q07 ssh --native-ssh=false
sudo -i
```

---

## 4. Answers

<details>
<summary>Click to reveal. Try it first!</summary>

The four steps from your notes: **config file → kubeconfig → mount volumes → enable the admission controller.**

### Step 1: Configuration file: implicit deny

```bash
cd /etc/kubernetes/epconfig
cat admission_configuration.json
vi admission_configuration.json
```

```json
          "defaultAllow": false
```

> **`defaultAllow`** decides what happens when the backend **can't be reached** (down, timeout, TLS error):
> - `true` = allow the pod (fail **open**). This is the starting value.
> - `false` = reject the pod (fail **closed**) = **"implicit deny"** ← the task
>
> It does **not** change what happens when the scanner answers "denied". That's always a deny.

### Step 2: Kubeconfig: point to the HTTPS endpoint

```bash
vi kubeconfig.yaml
```

```yaml
clusters:
- name: image-scanner
  cluster:
    certificate-authority: /etc/kubernetes/epconfig/scanner-ca.crt
    server: https://image-scanner.local:8081/image_policy     # was empty. Full URL incl. path, https
```

### Steps 3 + 4: kube-apiserver: enable the plugin, pass the config, mount the dir

```bash
cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/kube-apiserver.yaml.bak   # backup OUTSIDE manifests/
vi /etc/kubernetes/manifests/kube-apiserver.yaml
```

```yaml
    - --enable-admission-plugins=NamespaceLifecycle,...,ResourceQuota,ImagePolicyWebhook   # append
    - --admission-control-config-file=/etc/kubernetes/epconfig/admission_configuration.json
...
    volumeMounts:
    - mountPath: /etc/kubernetes/epconfig
      name: epconfig
      readOnly: true
...
  volumes:
  - hostPath:
      path: /etc/kubernetes/epconfig
      type: DirectoryOrCreate
    name: epconfig
```

Wait for the API server to come back (~30–60s):

```bash
watch crictl ps        # minikube: docker ps | grep kube-apiserver
k get nodes
```

### Test

```bash
k apply -f /root/q07/vulnerable-resource.yml
k get deploy vulnerable               # 0/1. The Deployment exists, but no Pod
k get events | grep FailedCreate
# ... pods "vulnerable-..." is forbidden: image policy webhook backend denied one or more images:
#     image scanner rejected vulnerable image(s): nginx:latest
tail /var/log/imagepolicy/scanner.log # ... images=nginx:latest allowed=False

k run ok --image=nginx:1.27-alpine    # pinned tag: allowed
```

Prove the implicit deny:

```bash
systemctl stop image-scanner
k run x --image=busybox:1.36.1 --dry-run=server
# Error from server (Forbidden): ... dial tcp 127.0.0.1:8081: connect: connection refused
systemctl start image-scanner
```

### Traps

| Trap | What happens |
|---|---|
| Plugin enabled but **no `--admission-control-config-file`** | API server **won't start**: ImagePolicyWebhook has no config |
| Config file not mounted (no hostPath) | API server **won't start**: the file doesn't exist inside the container. Also mount anything the config references (kubeconfig, certs). Here they're all in `epconfig/` |
| `server:` with `http://` or without `/image_policy` | Webhook call fails, so with `defaultAllow: false` **every new pod is denied** |
| Editing with a backup **inside** `manifests/` (e.g. `kube-apiserver.yaml.bak`) | The kubelet loads **every** file there. Both define pod `kube-apiserver-<node>`, so if your edited file is invalid, the kubelet quietly keeps running the **old .bak one**. "API server healthy", but your changes aren't live |
| Volume name with `_` (e.g. `admission_configuration`) | **Invalid**: names must be lowercase RFC 1123 (`a-z 0-9 -`). The kubelet rejects the whole manifest. `journalctl -u kubelet \| grep "Could not process manifest"` shows it. Use `admission-configuration` / `epconfig` |
| Testing with a Deployment and expecting an error from `kubectl apply` | ImagePolicyWebhook checks **Pods**. The Deployment is created fine. Look for **FailedCreate** events on the ReplicaSet |
| Re-testing the same image within 50s | `allowTTL`/`denyTTL: 50` cache the decision, so use a new tag |
| API server down, nothing works | `crictl ps -a \| grep apiserver`, `crictl logs <id>`, or `/var/log/pods/kube-system_kube-apiserver-*/` |

Scripted version: [`solution/solve.sh`](solution/solve.sh).

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
07-imagepolicywebhook/
  README.md
  setup.ps1                     node, scanner service, incomplete epconfig, test resource
  check.ps1                     grader (10 checks; stops the scanner briefly to test implicit deny)
  cleanup.ps1                   delete node
  setup/image-scanner.py        the HTTPS webhook backend (python, systemd)
  setup/break-node.sh           certs, scanner service, incomplete config
  setup/check.sh                grader logic
  yaml/vulnerable-resource.yml  Deployment with nginx:latest
  solution/solve.sh             scripted solution
```

Refs: [ImagePolicyWebhook admission controller](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/#imagepolicywebhook) · [kube-apiserver flags](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-apiserver/)
