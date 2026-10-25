# Q13 — Disable ServiceAccount token automount, mount a projected token read-only

Practice scenario: turn off ServiceAccount token automounting and mount a projected token read-only instead.

| | |
|---|---|
| Domain | Minimize Microservice Vulnerabilities / Cluster Hardening (ServiceAccounts) |
| Node | 1 × minikube `cks-q13` (2 CPU, 2 GB RAM) |
| Workload | namespace `monitoring`, ServiceAccount `stats-monitor-sa`, Deployment `stats-monitor` (busybox, 1 replica) |
| Grader | `.\check.ps1`: 14 checks |
| Target time | **6 minutes** |

> ⚠️ From Windows, always pass `--context cks-q13`. Never drop it: your kubeconfig may also contain real clusters.

---

## 1. Get ready (setup)

```powershell
cd 13-sa-projected-token
.\setup.ps1
```

This takes ~2 minutes and ends with `Ready. Start your timer…`. The grader starts at `3 / 14`:

```powershell
.\check.ps1
```

---

## 2. The task (start the timer)

> In namespace **`monitoring`**, Deployment **`stats-monitor`** uses ServiceAccount **`stats-monitor-sa`**. The Deployment's manifest is at `/opt/course/13/deployment.yaml`.
>
> 1. Modify ServiceAccount `stats-monitor-sa` to **turn off automounting** of API credentials.
> 2. Modify the Deployment so it mounts a ServiceAccount token using a **projected volume** named **`token`**:
>    - the token file must be at **`/var/run/secrets/kubernetes.io/serviceaccount/token`** inside the container
>    - the token must expire after **3600** seconds (`expirationSeconds`)
>    - the volume must be mounted **read-only**
> 3. Update the file `/opt/course/13/deployment.yaml` **and** apply it. The Pod must end up Running.

---

## 3. Log in

```powershell
minikube -p cks-q13 ssh --native-ssh=false
sudo -i
```

You have `k` / `kubectl` with Tab, and `$do`. Done? `exit` twice, then `.\check.ps1`.

---

## 4. Answers

<details>
<summary>Click to reveal. Try it first!</summary>

### Look first

```bash
k -n monitoring get sa stats-monitor-sa -o yaml
k -n monitoring get pod -o yaml | grep -A8 'volumes:'      # kube-api-access-xxxxx  <- auto-injected
k -n monitoring exec deploy/stats-monitor -- ls /var/run/secrets/kubernetes.io/serviceaccount
#   ca.crt  namespace  token
```

### 1. ServiceAccount: no automount

```bash
k -n monitoring edit sa stats-monitor-sa
```

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: stats-monitor-sa
  namespace: monitoring
automountServiceAccountToken: false     # top level, NOT under metadata/spec
```

(or `k -n monitoring patch sa stats-monitor-sa -p '{"automountServiceAccountToken": false}'`)

### 2. Deployment: projected token, read-only

```bash
vi /opt/course/13/deployment.yaml
```

```yaml
    spec:
      serviceAccountName: stats-monitor-sa
      containers:
      - name: stats-monitor
        image: busybox:1.36
        command: [...]
        volumeMounts:
        - name: token
          mountPath: /var/run/secrets/kubernetes.io/serviceaccount   # the DIRECTORY
          readOnly: true
      volumes:
      - name: token
        projected:
          sources:
          - serviceAccountToken:
              path: token                 # file name inside the mount -> .../serviceaccount/token
              expirationSeconds: 3600
              # audience: my-api          # optional; default = the API server's audience
```

```bash
k apply -f /opt/course/13/deployment.yaml
k -n monitoring rollout status deploy/stats-monitor
```

### 3. Verify

```bash
k -n monitoring get pod -o yaml | grep -E 'kube-api-access|name: token'   # only "token"
k -n monitoring exec deploy/stats-monitor -- ls /var/run/secrets/kubernetes.io/serviceaccount
#   token                      (no ca.crt / namespace now: you only projected the token)
TOKEN=$(k -n monitoring exec deploy/stats-monitor -- cat /var/run/secrets/kubernetes.io/serviceaccount/token)
k auth whoami --token "$TOKEN" --server https://127.0.0.1:8443 --insecure-skip-tls-verify --kubeconfig /dev/null
#   system:serviceaccount:monitoring:stats-monitor-sa
```

Full file: [`solution/deployment.yaml`](solution/deployment.yaml). Scripted: [`solution/solve.sh`](solution/solve.sh).

</details>

---

## Traps

| Trap | What to know |
|---|---|
| Where the field goes | `automountServiceAccountToken: false` is a **top-level** field of the ServiceAccount (next to `metadata`), and also exists in the **Pod spec** (`spec.template.spec`). |
| Precedence | The **Pod spec wins** over the SA. SA `false` + Pod `true` = token is mounted. The grader fails a Pod-level `true`. |
| SA change alone does nothing to running Pods | The token is injected by admission **when the Pod is created**. Patching only the SA leaves the old Pod with its `kube-api-access-*` volume until it is recreated. Here the Deployment template change rolls the Pod for you; if you only change the SA, you need `k rollout restart`. |
| Projected syntax | `volumes[].projected.sources[].serviceAccountToken.{path, expirationSeconds, audience}`. `path` is required. `expirationSeconds` must be ≥ 600. |
| Directory vs file | Mount the volume at the **directory** `/var/run/secrets/kubernetes.io/serviceaccount` and set `path: token`. Alternative: `mountPath: .../serviceaccount/token` **plus** `subPath: token` (accepted by the grader, but subPath mounts are **not refreshed** when kubelet rotates the token). `mountPath: .../serviceaccount/token` without subPath gives you `.../token/token`. |
| readOnly | Put `readOnly: true` on the **volumeMount**. (kubelet mounts projected volumes read-only anyway, but the task and the grader want it explicit.) |
| `k edit deploy` only | Changes the cluster but not the file. The task says update the file and apply. |
| `apply` after a different mountPath | `apply` merges volumeMounts **by mountPath**: if you applied one mountPath and then change it in the file, the old mount stays too. Check the live spec; use `k replace -f` (or delete the stale entry) if it's doubled. |
| Missing ca.crt / namespace | With only a `serviceAccountToken` source the dir contains only `token`. Apps that need `ca.crt` would need a `configMap` source (`kube-root-ca.crt`) and a `downwardAPI` source too. Not required here. |

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
13-sa-projected-token/
  README.md
  setup.ps1                   node, namespace + SA (automount on), Deployment, node tools
  check.ps1                   grader (14 checks)
  cleanup.ps1                 delete node
  setup/break-node.sh         runs on node: /opt/course/13/deployment.yaml, pre-pull busybox
  setup/check.sh              grader logic (live SA, Deployment spec, Pod volumes, token works via SelfSubjectReview, JWT exp-iat, file)
  yaml/serviceaccount.yaml    namespace + ServiceAccount (starting state)
  yaml/deployment.yaml        Deployment (starting state, → /opt/course/13/)
  solution/deployment.yaml    fixed manifest
  solution/solve.sh           scripted solution
```

Refs: [Configure Service Accounts for Pods (opt out of automounting)](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/#opt-out-of-api-credential-automounting) · [ServiceAccount token volume projection](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/#launch-a-pod-using-service-account-token-projection) · [Projected volumes](https://kubernetes.io/docs/concepts/storage/projected-volumes/)
