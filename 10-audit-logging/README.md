# Q10 — Audit logging: enable it, extend the policy, set log retention

Practice scenario: enable API server auditing with a policy at `/etc/kubernetes/logpolicy/sample-policy.yaml`, extend the policy, and configure log retention.

| | |
|---|---|
| Domain | Monitoring, Logging and Runtime Security / Cluster Setup |
| Node | 1 × minikube `cks-q10` (2 CPU, 2 GB RAM) |
| Starting state | Policy `/etc/kubernetes/logpolicy/sample-policy.yaml` with only a catch-all `Metadata` rule. Empty dir `/var/log/kubernetes`. Namespace `web`. **No audit flags** on the API server |
| Grader | `.\check.ps1`: 17 checks. It reads the manifest, the **running** process (`ps`), the container's mounts, then makes fresh requests (incl. as user `system:kube-proxy`) and reads the `level` each one was logged at |
| Target time | **10 minutes** |

---

## 1. Get ready (setup)

```powershell
cd 10-audit-logging
.\setup.ps1
```

This takes ~2 minutes and ends with `Ready…`. Grader start: `2 / 17`.

---

## 2. The task (start the timer)

> Turn on API server auditing on control-plane node `cks-q10`, using the log backend:
>
> - write the log to **`/var/log/kubernetes/audit-logs.txt`**
> - keep old log files for **10 days**
> - keep no more than **2** old log files
>
> Start from the policy at **`/etc/kubernetes/logpolicy/sample-policy.yaml`** (it currently only skips the `RequestReceived` stage). Extend it so that:
>
> - **`namespaces`** changes at **`RequestResponse`** level
> - the request body of **`secrets`** changes in the namespace **`web`**
> - all other resources in **`core`** and **`extensions`** at the **`Request`** level
> - do **not** log **`watch`** requests by **`system:kube-proxy`** on **`endpoints`** or **`services`**
> - all other requests at the **`Metadata`** level
>
> The running API server must be using your extended policy.

---

## 3. Log in

```powershell
minikube -p cks-q10 ssh --native-ssh=false
sudo -i
```

Done? `exit` twice, then `.\check.ps1`.

---

## 4. Answers

<details>
<summary>Click to reveal. Try it first!</summary>

### Step 1: Extend the policy (order matters: first match wins)

```bash
vi /etc/kubernetes/logpolicy/sample-policy.yaml
```

```yaml
apiVersion: audit.k8s.io/v1
kind: Policy
omitStages:
  - "RequestReceived"
rules:
  # None FIRST, or the broad "core at Request" rule below would catch these watches
  - level: None
    users: ["system:kube-proxy"]
    verbs: ["watch"]
    resources:
    - group: ""
      resources: ["endpoints", "services"]

  - level: RequestResponse
    resources:
    - group: ""
      resources: ["namespaces"]

  - level: Request
    resources:
    - group: ""
      resources: ["secrets"]
    namespaces: ["web"]

  - level: Request
    resources:
    - group: ""             # core
    - group: "extensions"   # group name only, no version

  # catch-all LAST
  - level: Metadata
```

> **Order.** The API server walks the rules top to bottom and uses the **first** rule that matches. The sample file's catch-all `- level: Metadata` must move to the **end**. If you leave it first, everything is logged at Metadata. The `None` rule and the specific rules go **above** the broad `group: ""` rule.
>
> **Levels:** `None` < `Metadata` (who/what/when, no bodies) < `Request` (+ request body) < `RequestResponse` (+ response body).

### Step 2: kube-apiserver: flags + mounts

```bash
cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/kube-apiserver.yaml.bak   # backup OUTSIDE manifests/
vi /etc/kubernetes/manifests/kube-apiserver.yaml
```

```yaml
  - command:
    - kube-apiserver
    - --audit-policy-file=/etc/kubernetes/logpolicy/sample-policy.yaml
    - --audit-log-path=/var/log/kubernetes/audit-logs.txt
    - --audit-log-maxage=10        # days to keep old files
    - --audit-log-maxbackup=2      # number of old files to keep
    ...
    volumeMounts:
    - mountPath: /etc/kubernetes/logpolicy/sample-policy.yaml
      name: audit-policy
      readOnly: true
    - mountPath: /var/log/kubernetes
      name: audit-logs              # NOT readOnly: the API server writes here
    ...
  volumes:
  - hostPath:
      path: /etc/kubernetes/logpolicy/sample-policy.yaml
      type: File
    name: audit-policy
  - hostPath:
      path: /var/log/kubernetes
      type: DirectoryOrCreate
    name: audit-logs
```

> You can also mount the whole `/etc/kubernetes/logpolicy` directory (`type: Directory`), or the log **file** with `type: FileOrCreate` (as in the docs example). Both are fine.

Wait for the API server to come back (~30–60s):

```bash
watch "docker ps | grep kube-apiserver"      # exam (containerd): watch crictl ps
k get nodes
```

### Step 3: Verify (the part people skip)

```bash
# 1. Is the RUNNING process using your flags? (catches a stale manifest / .bak being run)
ps -ef | grep [k]ube-apiserver | tr ' ' '\n' | grep audit

# 2. Is it logging?
tail -2 /var/log/kubernetes/audit-logs.txt

# 3. Do the rules match?
k create ns audit-test
k -n web create secret generic s1 --from-literal=a=b
k create cm c1 --from-literal=a=b
grep audit-test /var/log/kubernetes/audit-logs.txt | grep -o '"level":"[A-Za-z]*"' | sort | uniq -c   # RequestResponse
grep '"s1"'     /var/log/kubernetes/audit-logs.txt | grep -o '"level":"[A-Za-z]*"' | sort | uniq -c   # Request
grep '"c1"'     /var/log/kubernetes/audit-logs.txt | grep -o '"level":"[A-Za-z]*"' | sort | uniq -c   # Request
```

> The policy is read **only when the API server starts**. If you change the policy after the API server is already running with it, restart the API server: move the manifest out of `manifests/` and back, or make any change to it.

### Traps

| Trap | What happens |
|---|---|
| Flag points to a file that isn't **mounted** | API server **won't start**: the path doesn't exist inside the container. Mount the policy **and** the log location |
| Log location mounted `readOnly: true` | API server **won't start** (can't open the log file for writing) |
| `hostPath type: Directory` for a dir that doesn't exist, or `type: File` for a log file that doesn't exist yet | Pod fails to start. Use `DirectoryOrCreate` for the dir, or `FileOrCreate` for the file |
| Volume name with `_` (e.g. `audit_log`) | **Invalid**: names must be lowercase RFC 1123 (`a-z 0-9 -`). The kubelet rejects the whole manifest. `journalctl -u kubelet \| grep "Could not process manifest"` shows it. Use `audit-log` |
| Backup **inside** `manifests/` (e.g. `kube-apiserver.yaml.bak`) | The kubelet loads **every** file there. Both define pod `kube-apiserver-<node>`, so if your edit is invalid, the kubelet quietly runs the **old .bak**. "API server healthy", but no audit. Back up to `/root/`. Check the flags with `ps`, as in Step 3 |
| Catch-all `- level: Metadata` left at the **top** | Valid policy, API server healthy, log has entries, but **everything** is Metadata (first match wins) |
| `None` rule for kube-proxy placed **after** `group: ""` at Request | The watches still get logged at Request |
| `group: "extensions/v1beta1"` or `group: "core"` | The group is the name only. Core is `""` |
| Changing the policy while auditing is already on | No effect until the API server restarts |
| New `volumes:` items indented differently from the existing ones (3 spaces instead of 2) | `couldn't parse as pod(yaml: … mapping values are not allowed in this context)`. **No apiserver container at all** (`docker ps -a` shows nothing). Copy an existing `- hostPath:` block and keep its exact indentation. Volumes are at 2 spaces (`  - hostPath:`), mounts at 4 (`    - mountPath:`) |
| API server down, nothing works | `journalctl -u kubelet \| grep "Could not process manifest"`, `docker ps -a \| grep apiserver` + `docker logs <id>` (exam: `crictl ps -a`, `crictl logs`), or `/var/log/pods/kube-system_kube-apiserver-*/` |

**Retention flags:**

| Flag | Meaning |
|---|---|
| `--audit-log-maxage=10` | delete old (rotated) files older than **10 days** |
| `--audit-log-maxbackup=2` | keep at most **2** old files |
| `--audit-log-maxsize=100` | rotate when the file reaches **100 MB** (not asked here) |

Scripted version: [`solution/solve.sh`](solution/solve.sh) with [`solution/sample-policy.yaml`](solution/sample-policy.yaml).

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
10-audit-logging/
  README.md
  setup.ps1                    node, basic policy, namespace web, node tools
  check.ps1                    grader (17 checks; makes live requests, incl. as system:kube-proxy)
  cleanup.ps1                  delete node
  setup/break-node.sh          runs on node: policy, empty log dir, namespace web
  setup/check.sh               grader logic
  yaml/sample-policy.yaml      the basic (starting) policy
  solution/sample-policy.yaml  the extended policy
  solution/solve.sh            scripted solution (manifest edits)
```

Refs: [Auditing](https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/) · [Audit Policy API](https://kubernetes.io/docs/reference/config-api/apiserver-audit.v1/) · [kube-apiserver flags](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-apiserver/)
