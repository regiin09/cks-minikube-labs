# Q08 — Istio: sidecar injection + STRICT mTLS

Practice scenario: put a namespace in the Istio mesh (`istio-injection=enabled`) so a Deployment's Pods get sidecars, then enforce mTLS with a PeerAuthentication in mode **STRICT**.

| | |
|---|---|
| Domain | Minimize Microservice Vulnerabilities (mTLS / service mesh) |
| Node | 1 × minikube `cks-q08` (2 CPU, 3 GB RAM) |
| Istio | **1.31.2**, installed with `istioctl install --set profile=minimal` (istiod only, no gateways). `istioctl` is on the node with Tab completion |
| Workload | namespace **`shop`**: Deployment **`web`** (nginx) + Service **`web`** port 80. Starts **without** sidecars |
| Outsider | namespace **`legacy`** (not in the mesh): Deployment `legacy-client` (curl). Used to prove plaintext is refused |
| Grader | `.\check.ps1`: 8 checks, incl. a live in-mesh request (must work) and a plaintext request from `legacy` (must FAIL) |
| Target time | **6 minutes** |

---

## 1. Get ready (setup)

```powershell
cd 08-istio-mtls
.\setup.ps1
```

This takes ~7 minutes (pulls the Istio images, runs `istioctl install`) and ends with `Ready. Start your timer…`. Grader start: `1 / 8`.

---

## 2. The task (start the timer)

> Istio is installed in the cluster.
>
> 1. Enable Istio sidecar injection for namespace **`shop`** so that the Pods of Deployment **`web`** run with an Istio sidecar proxy.
> 2. Enforce mutual TLS for **all workloads in namespace `shop`**: create a PeerAuthentication named **`default`** with mTLS mode **`STRICT`**.
>
> Deployment `web` must stay available. Workloads outside the mesh must no longer be able to reach `web` in plaintext.

---

## 3. Log in

```powershell
minikube -p cks-q08 ssh --native-ssh=false
sudo -i
```

You have `k` / `kubectl` and `istioctl`, with Tab. Done? `exit` twice, then `.\check.ps1`.

---

## 4. Answers

<details>
<summary>Click to reveal. Try it first!</summary>

### 1. Label the namespace, then RESTART the Pods

```bash
k label ns shop istio-injection=enabled
k get ns shop --show-labels

k -n shop get pods                      # still 1/1: the label does nothing to running Pods!
k -n shop rollout restart deploy web
k -n shop rollout status deploy web
k -n shop get pods                      # READY 2/2  -> web + istio-proxy
```

> Injection is done by a **mutating admission webhook** (`istio-sidecar-injector`) when a Pod is **created**. Existing Pods are never changed. So after labelling you must recreate them: `rollout restart` (or delete the Pods).

Check the sidecar:

```bash
k -n shop get pod -l app=web -o jsonpath='{.items[0].spec.initContainers[*].name}{"  |  "}{.items[0].spec.containers[*].name}{"\n"}'
# istio-init istio-proxy  |  web
istioctl x describe pod $(k -n shop get pod -l app=web -o name | cut -d/ -f2) -n shop
istioctl proxy-status                   # web-....shop listed, connected to istiod
```

> On Istio ≥ 1.27 / Kubernetes ≥ 1.29 the sidecar is a **native sidecar**: `istio-proxy` is listed under **`initContainers`** (with `restartPolicy: Always`), not under `containers`. `k get pods` still shows **2/2**. Don't panic if `.spec.containers` only shows `web`.

### 2. PeerAuthentication, mode STRICT, in namespace shop

```bash
vi pa.yaml
```

```yaml
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: default
  namespace: shop            # namespace-wide. NOT istio-system
spec:
  mtls:
    mode: STRICT             # uppercase
```

```bash
k apply -f pa.yaml
k -n shop get peerauthentication       # short name: pa
```

> No `selector:` = applies to every workload in the namespace (that's what "all workloads in namespace shop" means).

### Test

```bash
# plaintext from outside the mesh -> refused (curl exit 56, "Connection reset by peer")
k -n legacy exec deploy/legacy-client -- curl -sS -m 5 http://web.shop.svc.cluster.local

# from inside the mesh -> works (the client's sidecar does the mTLS)
k -n shop run tmp --image=curlimages/curl:8.11.1 --command -- sleep 3600
k -n shop wait --for=condition=ready pod/tmp
k -n shop exec tmp -c tmp -- curl -s -o /dev/null -w '%{http_code}\n' http://web.shop.svc.cluster.local   # 200
k -n shop delete pod tmp
```

Before the PeerAuthentication, the legacy request **works** (default mode is PERMISSIVE: mTLS **and** plaintext are accepted).

### Traps

| Trap | What happens |
|---|---|
| Labelling the namespace and **not restarting** the Pods | Pods stay 1/1 without a sidecar (grader: 3 / 8). Injection only happens at Pod **creation**. `k -n shop rollout restart deploy web` |
| PeerAuthentication in **`istio-system`** (the root namespace) | That makes it **mesh-wide**, a different scope from "namespace shop". The traffic test passes, but the task asked for `default` **in `shop`**: the grader gives 5 / 8. Read the namespace in the task carefully |
| `mode: strict` / `Strict` / `mtls.Mode` / `mTLS:` | Mode must be exactly **`STRICT`** under `spec.mtls.mode`. `strict` is rejected by the CRD: `Unsupported value: "strict": supported values: "UNSET", "DISABLE", "PERMISSIVE", "STRICT"`. Keys are case-sensitive too: `mtls:` / `mode:`. Check with `k -n shop get pa` (MODE column must say STRICT) |
| `apiVersion: security.istio.io/v1beta1` | Still works on 1.31, but `v1` is current. Use `k explain peerauthentication.spec.mtls` if unsure |
| Adding a `selector:` | Then only matching Pods are STRICT, not "all workloads in the namespace" |
| STRICT on a namespace whose Pods have **no sidecar** | Nothing is enforced: the server-side sidecar does the check. So you need step 1 **and** step 2 |
| Label key typo (`istio-injection: enable`, `istio.io/rev`…) | Value must be **`enabled`**. `istio.io/rev=<rev>` is for revision-based installs; this cluster uses the default revision |
| Thinking `kubectl apply` of the Deployment injects the sidecar | Only if the Pod template changes. `rollout restart` adds an annotation to the template, which forces new Pods |
| Readiness probe failing after STRICT | Doesn't happen: Istio rewrites HTTP probes to go through the sidecar (`sidecar.istio.io/rewriteAppHTTPProbers`, on by default). `web` stays Ready |

Useful: `istioctl x describe pod <pod> -n shop`, `istioctl analyze -n shop`, `istioctl proxy-status`, `k -n shop get pods` (2/2).

Scripted version: [`solution/solve.sh`](solution/solve.sh).

</details>

---

## 5. Retry from scratch

Faster than rebuilding (Istio stays installed):

```bash
k label ns shop istio-injection-
k -n shop delete pa default
k -n shop rollout restart deploy web
```

Or `.\cleanup.ps1` then `.\setup.ps1`.

## 6. Delete the node (before the next question)

```powershell
.\cleanup.ps1
```

---

## Files

```
08-istio-mtls/
  README.md
  setup.ps1               node (2 CPU / 3 GB), node tools, Istio, workloads
  check.ps1               grader (8 checks; starts a temporary in-mesh curl Pod in shop)
  cleanup.ps1             delete node
  setup/node.sh           runs on node: istioctl 1.31.2, pre-pull images, istioctl install (minimal)
  setup/check.sh          grader logic
  yaml/workloads.yaml     shop/web (+Service), legacy/legacy-client
  solution/solve.sh       scripted solution
```

Refs: [Sidecar injection](https://istio.io/latest/docs/setup/additional-setup/sidecar-injection/) · [PeerAuthentication](https://istio.io/latest/docs/reference/config/security/peer_authentication/) · [Mutual TLS migration](https://istio.io/latest/docs/tasks/security/authentication/mtls-migration/) · [istioctl install](https://istio.io/latest/docs/setup/install/istioctl/)
