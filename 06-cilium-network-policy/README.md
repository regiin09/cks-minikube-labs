# Q06 — CiliumNetworkPolicy: mutual auth, host entity, egressDeny

Practice scenario: CiliumNetworkPolicies with mutual authentication, the `host` entity, and `egressDeny`.

| | |
|---|---|
| Domain | Minimize Microservice Vulnerabilities / Cluster Setup (network policies) |
| Node | 1 × minikube `cks-q06` (**3 CPU, 3 GB**; Cilium + SPIRE need it) |
| CNI | **Cilium 1.20.3** (Helm) with **SPIRE mutual authentication**. `cilium` CLI on the node |
| Workloads | `payments`: Deployments `api`, `metrics` (+ Services). `checkout`: `client`. `marketing`: `client` |
| Grader | `.\check.ps1`: 14 checks, the **policy spec AND real traffic** (including that a SPIRE handshake happened) |
| Target time | **12 minutes** |
| Needs on your PC | `helm` (you have it) |

---

## 1. Get ready (setup)

```powershell
cd 06-cilium-network-policy
.\setup.ps1
```

This takes ~7–8 minutes (Cilium + SPIRE). It ends with `Ready. Start your timer…`. Starting state: everything can talk to everything, and the grader shows `2 / 14`:

```powershell
.\check.ps1
```

---

## 2. The task (start the timer)

> The cluster uses Cilium with mutual authentication (SPIRE) enabled. Create these **CiliumNetworkPolicies**:
>
> 1. **`api-ingress`** in namespace `payments`
>    - applies to the Pods of Deployment **`api`** (`app=api`)
>    - allows ingress **only** from Pods in namespace **`checkout`**, on **80/TCP**
>    - this traffic must **require mutual authentication**
>
> 2. **`metrics-from-host`** in namespace `payments`
>    - applies to the Pods of Deployment **`metrics`** (`app=metrics`)
>    - allows ingress from the **host** (the node itself) on **80/TCP**, **without** mutual authentication
>    - nothing else may reach these Pods
>
> 3. **`deny-world`** in namespace `checkout`
>    - applies to **all** Pods in the namespace
>    - **denies** egress to the internet (outside the cluster) with an **`egressDeny`** rule
>    - all other egress (DNS, other Pods) must keep working

---

## 3. Log in (optional: you can also do it all from PowerShell with `--context cks-q06`)

```powershell
minikube -p cks-q06 ssh --native-ssh=false
sudo -i
```

You have `k`/`kubectl` with Tab, and `cilium` (`cilium status`, `cilium config view`).

Test traffic yourself:

```bash
k -n checkout  exec deploy/client -- curl -s -m5 -o /dev/null -w '%{http_code}\n' http://api.payments      # 200
k -n marketing exec deploy/client -- curl -s -m5 -o /dev/null -w '%{http_code}\n' http://api.payments      # 000 when done
k -n checkout  exec deploy/client -- curl -s -m5 -o /dev/null -w '%{http_code}\n' https://1.1.1.1           # 000 when done
curl -s -m5 -o /dev/null -w '%{http_code}\n' http://$(k -n payments get pod -l app=metrics -o jsonpath='{.items[0].status.podIP}')   # from the node = host: 200
```

---

## 4. Answers

<details>
<summary>Click to reveal. Try it first!</summary>

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: api-ingress
  namespace: payments
spec:
  endpointSelector:
    matchLabels:
      app: api
  ingress:
  - fromEndpoints:
    - matchLabels:
        k8s:io.kubernetes.pod.namespace: checkout     # "all Pods in namespace checkout"
    toPorts:
    - ports:
      - port: "80"
        protocol: TCP
    authentication:
      mode: "required"                                # mutual auth (SPIRE)
---
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: metrics-from-host
  namespace: payments
spec:
  endpointSelector:
    matchLabels:
      app: metrics
  ingress:
  - fromEntities:
    - host                                            # the node: kubelet probes, node agents
    toPorts:
    - ports:
      - port: "80"
        protocol: TCP
    # no "authentication:" block = no mutual auth
---
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: deny-world
  namespace: checkout
spec:
  endpointSelector: {}                                # all Pods in the namespace
  egress:
  - toEntities:
    - all                                             # keep everything else working …
  egressDeny:
  - toEntities:
    - world                                           # … except the internet. Deny always wins.
```

```bash
k apply -f policies.yaml
k get cnp -A                                          # VALID = True
```

Full file: [`solution/policies.yaml`](solution/policies.yaml).

### Check that mutual auth really happened

```bash
k -n checkout exec deploy/client -- curl -s -o /dev/null -w '%{http_code}\n' http://api.payments   # 200
k -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg bpf auth list
#  SRC IDENTITY   DST IDENTITY   REMOTE NODE ID   AUTH TYPE   EXPIRATION
#  946            22970          0                spire       …        ← a SPIRE handshake happened
k -n kube-system logs ds/cilium -c cilium-agent | grep -i "successfully authenticated"
```

### Traps (each one was verified in this lab)

| Trap | What actually happens |
|---|---|
| **`egressDeny` alone** (no `egress:` allow) | **Blocks ALL egress** of those Pods: the api, DNS, everything, not just `world`. Any policy that selects a Pod puts it in **default-deny** for that direction. Add `egress: - toEntities: [all]` and let `egressDeny` carve out `world`. |
| Deny vs allow | `ingressDeny`/`egressDeny` **always win** over any allow, in any policy. |
| `authentication` placement | It sits on the **rule** (same level as `fromEndpoints`/`toPorts`), not under `spec` or `toPorts`. Value `mode: "required"`. |
| Namespace selector | In Cilium it's a **label** on the endpoint: `k8s:io.kubernetes.pod.namespace: checkout`. There is no `namespaceSelector` like in a k8s NetworkPolicy. |
| `fromEntities: host` | This is the **local node**. Other nodes are `remote-node`. Host → pod usually works anyway (kubelet probes), so the point is that the policy allows **only** the host. |
| Port as string | `port: "80"` (string), `protocol: TCP` (caps). |

### Cilium entities cheat sheet

| Entity | Means |
|---|---|
| `host` | the local node (and host-network pods on it) |
| `remote-node` | other nodes in the cluster |
| `kube-apiserver` | the Kubernetes API server |
| `cluster` | everything inside the cluster (pods, nodes, host) |
| `world` | everything **outside** the cluster (= 0.0.0.0/0 minus cluster) |
| `all` | `cluster` + `world` |
| `health`, `init`, `unmanaged`, `ingress` | Cilium health endpoints, endpoints not yet identified, pods not managed by Cilium, Cilium's ingress proxy |

</details>

---

## 5. Retry from scratch

Either delete the policies (`k delete cnp -A --all`, which brings you back to the start state) or `.\cleanup.ps1` then `.\setup.ps1`.

## 6. Delete the node (before the next question)

```powershell
.\cleanup.ps1
```

---

## Lab notes

- Cilium is installed with Helm from your PC using [`yaml/cilium-values.yaml`](yaml/cilium-values.yaml): `authentication.enabled`, `authentication.mutual.spire.enabled` and `…spire.install.enabled`.
- The chart's default **SPIRE 1.15.3 server** starts and immediately stops its APIs on this minikube/WSL2 setup (the health port never opens and the liveness probe kills it). The values pin **SPIRE 1.9.6**, which works. The exam cluster comes with SPIRE already running.
- Setup recreates CoreDNS and the SPIRE pods after Cilium is up, because pods started before Cilium got minikube's bridge IPs.

## Files

```
06-cilium-network-policy/
  README.md
  setup.ps1                    node (no CNI), helm install Cilium+SPIRE, cilium CLI, workloads
  check.ps1                    grader (14 checks: spec + live traffic + SPIRE auth map)
  cleanup.ps1                  delete node
  setup/node.sh                cilium CLI on the node
  setup/check.sh               grader logic
  yaml/cilium-values.yaml      Helm values (mutual auth, SPIRE 1.9.6)
  yaml/workloads.yaml          namespaces, api/metrics/clients
  solution/policies.yaml       the three CNPs
```

Refs: [Cilium policy language (entities, deny)](https://docs.cilium.io/en/stable/security/policy/language/) · [Mutual authentication](https://docs.cilium.io/en/stable/network/servicemesh/mutual-authentication/mutual-authentication/) · [Mutual auth example](https://docs.cilium.io/en/stable/network/servicemesh/mutual-authentication/mutual-authentication-example/)
