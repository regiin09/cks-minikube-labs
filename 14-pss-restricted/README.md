# Q14 — Restricted Pod Security Standard: fix the Deployment so its Pods are admitted

Practice scenario: make a Deployment compliant with the `restricted` Pod Security Standard.

| | |
|---|---|
| Domain | Minimize Microservice Vulnerabilities (Pod Security Admission) |
| Node | 1 × minikube `cks-q14` (2 CPU, 2 GB RAM, Docker driver, docker runtime) |
| Kubernetes | v1.35.1 |
| Workload | namespace `team-red` (`enforce=restricted`), Deployment `web-server` (2 replicas, `nginxinc/nginx-unprivileged`, port 8080) |
| Randomised | 4 violations always + **2 of 5 extras picked at random each setup** (`privileged`, `runAsUser: 0`, `capabilities.add NET_ADMIN`, `hostNetwork`, `hostPath` volume) |
| Grader | `.\check.ps1`: 11 checks |
| Target time | **6 minutes** |

> ⚠️ Every `kubectl` command from Windows uses `--context cks-q14`. Never drop it: your kubeconfig may also contain real clusters.

---

## 1. Get ready (setup)

```powershell
cd 14-pss-restricted
.\setup.ps1
```

This takes ~2–3 minutes and ends with `Ready. Start your timer…`. The grader starts at about `2 / 11`:

```powershell
.\check.ps1
```

---

## 2. The task (start the timer)

> The namespace **`team-red`** enforces the **restricted** Pod Security Standard. The Deployment **`web-server`** in that namespace has no running Pods.
>
> 1. Find out why the Pods are not created.
> 2. Fix the Deployment **`web-server`** so that its Pods are admitted and **Running**. The manifest is at **`/opt/course/14/deployment.yaml`**: update the file **and** apply it.
> 3. **Do not** change the namespace labels. Do not change the image.

---

## 3. Log in

```powershell
minikube -p cks-q14 ssh --native-ssh=false
sudo -i
```

(Exam equivalent: `ssh cks-q14`, `sudo -i`.) You have `k` / `kubectl` with Tab and `$do`. Done? `exit` twice, then `.\check.ps1`.

---

## 4. Answers

<details>
<summary>Click to reveal. Try it first!</summary>

### 1. Read why the Pods are rejected

The Deployment exists, but there are **no Pods at all** (not even Pending). PSA rejects the Pod at admission, so the error is on the **ReplicaSet**:

```bash
k -n team-red get deploy,rs,pod
k -n team-red describe rs -l app=web-server | grep -m1 FailedCreate
# or
k -n team-red get events --field-selector reason=FailedCreate
```

The message lists every violation, for example:

```
violates PodSecurity "restricted:latest": privileged (container "nginx" must not set securityContext.privileged=true),
allowPrivilegeEscalation != false (...), unrestricted capabilities (... capabilities.drop=["ALL"]),
runAsNonRoot != true (pod or container "nginx" ...), runAsUser=0 (...), seccompProfile (pod or container "nginx" ...)
```

> This message is your checklist. "pod or container" means the field may go at either level.

### 2. Fix the manifest

```bash
vi /opt/course/14/deployment.yaml
```

```yaml
    spec:
      securityContext:                 # POD level (spec.template.spec.securityContext)
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: nginx
        image: nginxinc/nginx-unprivileged:1.27-alpine
        ports:
        - containerPort: 8080
        securityContext:               # CONTAINER level
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
```

and **delete** whichever extras your setup added: `privileged: true`, `runAsUser: 0`, `capabilities.add: ["NET_ADMIN"]`, `hostNetwork: true`, the `hostPath` volume plus its `volumeMounts`. (Need the volume? Swap `hostPath:` for `emptyDir: {}`.)

```bash
k apply -f /opt/course/14/deployment.yaml
k -n team-red rollout status deploy/web-server
k -n team-red get pod                                     # 2/2 Running
k -n team-red exec deploy/web-server -- id                # uid=101(nginx)
```

Full file: [`solution/deployment.yaml`](solution/deployment.yaml). Scripted: [`solution/solve.sh`](solution/solve.sh).

> **Fast check before applying**: `k apply -f /opt/course/14/deployment.yaml --dry-run=server` prints `Warning: would violate PodSecurity ...` if anything is still wrong. No warning = admitted.

### Restricted profile cheat sheet

| Field | Where | Value |
|---|---|---|
| `allowPrivilegeEscalation` | **container** only | `false` |
| `capabilities.drop` | **container** only | `["ALL"]` (add only `NET_BIND_SERVICE`) |
| `runAsNonRoot` | pod **or** container | `true` |
| `runAsUser` | pod or container | anything but `0` |
| `seccompProfile.type` | pod **or** container | `RuntimeDefault` or `Localhost` |
| `privileged` | container | not `true` |
| `hostNetwork/hostPID/hostIPC`, `hostPort`, `hostPath` volumes | pod | not allowed (already baseline) |
| volume types | pod | only configMap, secret, emptyDir, projected, downwardAPI, PVC, ephemeral, csi |

</details>

---

## Traps

| Trap | What happens |
|---|---|
| Looking at `k get pod` / `k describe pod` | There is no Pod to describe. The reason is on the **ReplicaSet** (`describe rs`) or in `get events`. |
| `allowPrivilegeEscalation` / `capabilities` at **pod** level | They don't exist in the PodSecurityContext. `kubectl apply` fails with `strict decoding error: unknown field "spec.securityContext.allowPrivilegeEscalation"`. Container level only. |
| `drop: ["all"]` | Must be uppercase `ALL`. Lower case does not satisfy restricted. |
| Only `runAsNonRoot: true`, image runs as root | Admitted by PSA, but the kubelet refuses: `CreateContainerConfigError: container has runAsNonRoot and image will run as root`. Needs an image with a **numeric** non-root `USER`, or `runAsUser: 1000`. |
| `runAsNonRoot: true` + leftover `runAsUser: 0` | Still rejected (`runAsUser=0`). Delete it. |
| Switching to `nginx:latest` | Runs as root and binds :80. Rejected by the kubelet with runAsNonRoot, or crashloops as non-root. Keep `nginx-unprivileged` on 8080. |
| Changing the namespace label to `baseline`/`privileged` (or deleting it) | Pods start, but the grader FAILS: the task says don't touch the labels. |
| `k edit deploy` only | Cluster fixed, file still wrong. The grader dry-runs the **file** too. |
| Old ReplicaSet Pods | If the new template is still rejected, the rollout hangs. Check `rollout status`, not just "some pods Running". |

---

## 5. Retry from scratch

`.\cleanup.ps1` then `.\setup.ps1` (~3 min). The 2 extra violations change each time.

## 6. Delete the node (before the next question)

```powershell
.\cleanup.ps1
```

or `minikube delete -p cks-q14`. Setup uses `--keep-context`, so your current kubectl context is never switched.

---

## Files

```
14-pss-restricted/
  README.md
  setup.ps1                   node, task file, namespace + broken Deployment (2 random extras)
  check.ps1                   grader (11 checks)
  cleanup.ps1                 delete node
  setup/break-node.sh         runs on node: /opt/course/14/deployment.yaml, pre-pull image
  setup/check.sh              grader logic (field checks + server dry-run of live and file templates)
  yaml/namespace.yaml         team-red, enforce=restricted
  yaml/deployment.yaml        template with "#x:" extras (setup keeps 2)
  solution/deployment.yaml    fixed
  solution/solve.sh           scripted solution
```

Refs: [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/) · [Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/) · [Enforce PSS with namespace labels](https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/) · [Security context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)
