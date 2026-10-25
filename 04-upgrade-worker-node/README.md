# Q04 — Upgrade the worker node (one patch behind)

Practice scenario: upgrade a kubeadm worker node that is one patch version behind the control plane.

| | |
|---|---|
| Domain | Cluster Setup / Cluster Hardening (keep components up to date) |
| Nodes | 2 × minikube: control plane **`cks-q04`** (v1.35.1) + worker **`cks-q04-m02`** (v1.35.0) |
| On the worker | `kubeadm`, `kubelet`, `kubectl` **1.35.0-1.1** from `pkgs.k8s.io`, all `apt-mark hold`, exactly like a kubeadm exam node |
| SSH | from the control plane as root: **`ssh node01`** (or `ssh cks-q04-m02`), then `sudo -i` |
| Workloads | `web` (4 replicas), `cache` (emptyDir, pinned to the worker), `standalone` (bare Pod on the worker) |
| Grader | `.\check.ps1`: 11 checks |
| Resources | 2 nodes × (2 CPU, 2 GB) |
| Target time | **8 minutes** |

> ⚠️ Every `kubectl` from Windows uses `--context cks-q04`. Setup uses `--keep-context`, so your current context isn't switched.

---

## 1. Get ready (setup)

```powershell
cd 04-upgrade-worker-node
.\setup.ps1
```

This takes ~4 minutes (two nodes, plus apt installs on the worker). It ends with:

```
NAME          STATUS   ROLES           VERSION
cks-q04       Ready    control-plane   v1.35.1
cks-q04-m02   Ready    <none>          v1.35.0
Ready. Start your timer…
```

The grader shows the starting state (`6 / 11`):

```powershell
.\check.ps1
```

---

## 2. The task (start the timer)

> The worker node **`cks-q04-m02`** is running a kubelet one patch version behind the control plane.
>
> Upgrade **kubeadm, kubelet and kubectl** on `cks-q04-m02` to **exactly the version of the control plane**. Do not upgrade the control plane.
>
> - Drain the node first and make it schedulable again afterwards.
> - Leave the packages **held** when you're done.
> - All workloads must be running afterwards.
>
> You can SSH to the worker from the control plane with `ssh node01`.

---

## 3. Log in

```powershell
minikube -p cks-q04 ssh --native-ssh=false
sudo -i
```

You're on the **control plane** with `kubectl`, `k`, Tab completion and `$do`. From here:

```bash
ssh node01        # lands as user docker on the worker
sudo -i           # root on the worker
```

Done? `exit` your way out, then `.\check.ps1` from PowerShell.

---

## 4. Answers

<details>
<summary>Click to reveal. Try it first!</summary>

```bash
# ── control plane ──────────────────────────────────────────────
k get nodes                          # CP v1.35.1 → that's the target. Worker v1.35.0
k drain cks-q04-m02 --ignore-daemonsets --delete-emptydir-data --force

ssh node01
sudo -i

# ── worker ─────────────────────────────────────────────────────
apt update
apt-cache madison kubeadm | grep 1.35.1        # → 1.35.1-1.1
apt-mark unhold kubeadm
apt-get install -y kubeadm=1.35.1-1.1
apt-mark hold kubeadm
kubeadm version -o short                       # v1.35.1

kubeadm upgrade node                           # worker: just "upgrade node", NOT "upgrade apply"

apt-mark unhold kubelet kubectl
apt-get install -y kubelet=1.35.1-1.1 kubectl=1.35.1-1.1
apt-mark hold kubelet kubectl

systemctl daemon-reload
systemctl restart kubelet
exit; exit                                     # back to the control plane

# ── control plane ──────────────────────────────────────────────
k uncordon cks-q04-m02
k get nodes                                    # both v1.35.1, Ready
```

### Traps (each one costs points)

| Trap | What happens |
|---|---|
| Installing the **top** line of `apt-cache madison` (1.35.9) | Kubelet would be **newer** than the API server, which isn't allowed. Always match the **control plane** version: `k get nodes`. |
| `kubeadm upgrade apply` on the worker | That's for the control plane. On a worker it's **`kubeadm upgrade node`**. |
| Forgetting `apt-mark hold` again | Packages drift on the next `apt upgrade`. The grader checks all three are held. |
| Forgetting `uncordon` | Node stays `SchedulingDisabled`. Here `cache` (pinned to the worker) stays **Pending**, and the grader catches it. |
| Missing drain flags | `--ignore-daemonsets` (kube-proxy), `--delete-emptydir-data` (`cache`), `--force` (bare pod `standalone`). Without them, drain refuses. |
| Package version format | It's `1.35.1-1.1` on pkgs.k8s.io, not `1.35.1-00` (that was the old apt.kubernetes.io format). Copy it from `madison`. |
| Running `drain` on the worker | The worker has no admin kubeconfig. Drain and uncordon from the **control plane**. |

`standalone` is gone after the drain and doesn't come back. That's expected: bare pods have no controller, which is why `--force` is needed.

Full script: [`solution/upgrade-worker.md`](solution/upgrade-worker.md).

</details>

---

## 5. Retry from scratch

`.\cleanup.ps1` then `.\setup.ps1` (~5 min).

## 6. Delete the nodes (before the next question)

```powershell
.\cleanup.ps1
```

or `minikube delete -p cks-q04`. This deletes both nodes.

---

## How the lab fakes an older worker

minikube normally runs every node from the same `/var/lib/minikube/binaries/v1.35.1/`. Setup:
1. adds the `pkgs.k8s.io/core:/stable:/v1.35/deb/` apt repo on the worker
2. installs `kubeadm/kubelet/kubectl=1.35.0-1.1` and holds them
3. points the kubelet unit (`/etc/systemd/system/kubelet.service.d/10-kubeadm.conf`) at `/usr/bin/kubelet`

So the worker really runs an apt-managed v1.35.0 kubelet, and the exam steps work unchanged.

## Files

```
04-upgrade-worker-node/
  README.md
  setup.ps1                     2 nodes, worker → 1.35.0 via apt, ssh node01, workloads
  check.ps1                     grader (11 checks)
  cleanup.ps1                   delete both nodes
  setup/master.sh               runs on control plane: root ssh key + "node01" ssh config
  setup/worker.sh               runs on worker: apt repo, 1.35.0 packages held, kubelet unit → /usr/bin/kubelet
  setup/check.sh                grader logic (runs on control plane, ssh's to node01)
  yaml/workloads.yaml           web / cache (emptyDir) / standalone (bare pod)
  solution/upgrade-worker.md
```

Refs: [Upgrading kubeadm clusters: worker nodes](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/upgrading-linux-nodes/) · [Version skew policy](https://kubernetes.io/releases/version-skew-policy/) · [Safely drain a node](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/)
