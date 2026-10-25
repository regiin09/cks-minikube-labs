# Q11 — NetworkPolicy: deny all ingress, allow only from one namespace

Practice scenario: default-deny ingress plus allow-from-one-namespace with plain `networking.k8s.io/v1` NetworkPolicies (not Cilium).

| | |
|---|---|
| Domain | Cluster Setup (network policies) |
| Node | 1 × minikube `cks-q11` (2 CPU, 2 GB RAM) |
| CNI | **Calico** (`minikube start --cni=calico`), which **enforces** NetworkPolicy |
| Workloads | `prod`: Deployments `web`, `api` (+ Services) and `client`. An **allowed** namespace with `client`. A **not-allowed** namespace with `client` and `web` (+ Service) |
| Random | The allowed / not-allowed namespace names are **picked at random each setup** (`frontend`, `monitoring`, `partners`, `staging`, `analytics`) |
| Grader | `.\check.ps1`: 15 checks, the **policy spec AND real traffic** |
| Target time | **6 minutes** |

---

## 1. Get ready (setup)

```powershell
cd 11-networkpolicy
.\setup.ps1
```

This takes ~3–4 minutes and ends with `Allowed namespace this run: <ns>` and `Ready. Start your timer…`. Starting state: no policies, everything can talk to everything. The grader shows `5 / 15`:

```powershell
.\check.ps1
```

---

## 2. The task (start the timer)

The namespace name for this run is in **`/opt/course/11/task.txt`** on the node (written as `<allowed>` below).

> Namespace **`prod`** runs Deployments `web` and `api` (with Services) and a `client`.
>
> 1. Create a NetworkPolicy **`deny-all-ingress`** in namespace `prod` that **denies all ingress** traffic to **all Pods** in `prod`.
> 2. Create a NetworkPolicy **`allow-from-<allowed>`** in namespace `prod` that allows ingress to all Pods in `prod` **only from Pods in namespace `<allowed>`**. Select the namespace with the label **`kubernetes.io/metadata.name`**.
> 3. Do **not** restrict egress.

---

## 3. Log in (optional: you can also do it all from PowerShell with `--context cks-q11`)

```powershell
minikube -p cks-q11 ssh --native-ssh=false
sudo -i
cat /opt/course/11/task.txt
```

Test traffic yourself (replace `staging` / `frontend` with this run's names):

```bash
k -n staging  exec deploy/client -- curl -s -m4 -o /dev/null -w '%{http_code}\n' http://web.prod       # 200
k -n frontend exec deploy/client -- curl -s -m4 -o /dev/null -w '%{http_code}\n' http://web.prod       # 000 when done
k -n prod     exec deploy/client -- curl -s -m4 -o /dev/null -w '%{http_code}\n' http://api.prod       # 000 when done (same ns!)
k -n prod     exec deploy/client -- curl -s -m4 -o /dev/null -w '%{http_code}\n' http://web.frontend   # 200 (egress untouched)
```

---

## 4. Answers

<details>
<summary>Click to reveal. Try it first!</summary>

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-ingress
  namespace: prod
spec:
  podSelector: {}            # all Pods in prod
  policyTypes:
  - Ingress                  # Ingress listed, no ingress rules = deny all ingress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-staging   # allow-from-<allowed>
  namespace: prod
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: staging   # <allowed>
```

```bash
k apply -f np.yaml
k -n prod get netpol
k -n prod describe netpol allow-from-staging
```

Fast start: `k -n prod get ns staging --show-labels` shows the automatic `kubernetes.io/metadata.name=staging` label. Copy the skeleton from the docs page "Network Policies" (`default-deny-ingress` example).

Scripted version: [`solution/solve.sh`](solution/solve.sh) (reads the name from task.txt). Plain YAML: [`solution/policies.yaml`](solution/policies.yaml).

### Traps (each one was verified in this lab)

| Trap | What actually happens |
|---|---|
| **AND vs OR: the dash** | `- namespaceSelector: …` **and** `- podSelector: {}` as **two list items** = **OR**: "Pods from `<allowed>`" **or** "any Pod in `prod`". That re-opens `prod → prod`. The grader catches it (12/15). One item with both keys (`- namespaceSelector: …` then `  podSelector: …` with no dash) = **AND**: Pods matching podSelector **inside** namespaces matching namespaceSelector. |
| `podSelector` alone in `from` | Matches Pods **only in the policy's own namespace** (`prod`), never in other namespaces. |
| `namespaceSelector: {}` | **All namespaces**: the not-allowed namespace gets in too (9/15). |
| Namespace label | Every namespace gets `kubernetes.io/metadata.name=<name>` automatically (k8s ≥1.21). Don't invent `name: staging`: the namespace doesn't have that label, so nothing would match. |
| Deny-all covers the same namespace | After `deny-all-ingress`, Pods in `prod` can't reach each other either. Only `<allowed>` is allowed back in. |
| `policyTypes: [Ingress, Egress]` on deny-all | Also blocks **all egress** of `prod`, including DNS (11/15). The task says don't touch egress: list only `Ingress`. |
| Policies are additive | There is no "deny" rule in k8s NetworkPolicy. A Pod selected by any policy is default-deny for that direction; the allows from all policies are added together. |
| NetworkPolicy vs CiliumNetworkPolicy | k8s NP: `podSelector` + `namespaceSelector`, `policyTypes`, no deny rules, no L7. Cilium CNP (Q06): `endpointSelector`, namespace is the label `k8s:io.kubernetes.pod.namespace`, has `ingressDeny`/`egressDeny`, entities (`host`, `world`), L7 rules. Read which kind the task asks for. |

</details>

---

## 5. Retry from scratch

`k -n prod delete netpol --all` brings you back to the start state. Or `.\cleanup.ps1` then `.\setup.ps1` (new random namespace names).

## 6. Delete the node (before the next question)

```powershell
.\cleanup.ps1
```

---

## Lab notes

- minikube's default network (bridge / kindnet) **does not enforce** NetworkPolicy: the objects are accepted but nothing is blocked. That's why this lab uses `--cni=calico`. Enforcement was verified: with the solution, the not-allowed namespace and `prod` itself get `000` (timeout).
- Setup restarts CoreDNS after Calico is up, because pods started before the CNI may have minikube's bridge IPs.

## Files

```
11-networkpolicy/
  README.md
  setup.ps1                 node with Calico, random namespace names, task file, workloads
  check.ps1                 grader (15 checks: spec + live traffic)
  cleanup.ps1               delete node
  setup/break-node.sh       runs on node: /opt/course/11/task.txt + grader key
  setup/check.sh            grader logic
  yaml/workloads.yaml       template (namespace names filled in by setup)
  solution/policies.yaml    the two policies (ALLOWED placeholder)
  solution/solve.sh         scripted solution
```

Refs: [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/) · [Default deny all ingress](https://kubernetes.io/docs/concepts/services-networking/network-policies/#default-deny-all-ingress-traffic) · [Behavior of to and from selectors](https://kubernetes.io/docs/concepts/services-networking/network-policies/#behavior-of-to-and-from-selectors) · [Automatic namespace label](https://kubernetes.io/docs/reference/labels-annotations-taints/#kubernetes-io-metadata-name)
