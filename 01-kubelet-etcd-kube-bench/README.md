# Q01 — Fix insecure kubelet and etcd (kube-bench / CIS)

| | |
|---|---|
| Domain | Cluster Setup — CIS benchmark |
| Node | 1 × minikube control-plane `cks-q01` (2 CPU, 2 GB RAM, Docker driver) |
| Kubernetes | v1.35.1 → kube-bench picks benchmark `cis-2.0` |
| Tools on node | `kube-bench` v0.16.0 (pre-installed by setup) |
| Grader | `.\check.ps1`: 15 checks (cluster health, the 7 kube-bench checks, "done properly"). Starts at `6 / 15` |
| Target time | **8 minutes** (exam weight ~7%) |

> ⚠️ Your kubeconfig may also contain real clusters.
> Every `kubectl` command here uses `--context cks-q01`. Never drop it.

---

## 1. Get ready (setup)

Run in **PowerShell** from this folder:

```powershell
cd 01-kubelet-etcd-kube-bench
.\setup.ps1
```

When you finish, grade yourself from PowerShell:

```powershell
.\check.ps1
```

It also catches common mistakes: a duplicate or quoted `--client-cert-auth`, and stray files (such as `.swp` or `.bak`) in `manifests/`.

Takes ~2 minutes. It ends with `>> done. Node is ready for the question.`

etcd restarts once during setup. Give it ~30s, then confirm it's `1/1 Running` before you start the timer:

```powershell
kubectl --context cks-q01 get pods -n kube-system
```

> Git Bash users: prefix the last two commands with `MSYS_NO_PATHCONV=1` or `/tmp` gets rewritten to a Windows path.

---

## 2. The task (read this, start the timer)

> A CIS Benchmark tool was run against the kubeadm-provisioned cluster and found multiple issues that must be addressed immediately.
>
> SSH to the control-plane node `cks-q01`. Use `kube-bench` to find the issues, then fix **all** of the following:
>
> **kubelet**
> - Ensure the `--anonymous-auth` argument is set to `false`.
> - Ensure the `--authorization-mode` argument is set to `Webhook`.
>
> **etcd**
> - Ensure the `--client-cert-auth` argument is set to `true`.
> - Ensure the `--auto-tls` argument is not set to `true`.
> - Ensure the `--peer-auto-tls` argument is not set to `true`.
> - Ensure the etcd data directory permissions are `700` or more restrictive.
> - Ensure the etcd data directory ownership is `etcd:etcd`. The `etcd` user does not exist on this node. Create it.
>
> Leave all other FAILs alone (they come from minikube's layout, not the task). The cluster must still be healthy when you finish.

---

## 3. Log in to the node

```powershell
minikube -p cks-q01 ssh --native-ssh=false
sudo -i
```

(The exam equivalent is `ssh cks-q01` then `sudo -i`.)

> `--native-ssh=false` makes minikube use Windows OpenSSH (`ssh.exe`). The default Go SSH client breaks arrow keys, history and Tab completion. If it still misbehaves, use `docker exec -it cks-q01 bash`, which drops you straight into a root shell on the node.

Find the issues:

```bash
kube-bench run --targets master,etcd,node | grep FAIL
# or narrow it down
kube-bench run --targets etcd
kube-bench run --targets node  --check 4.2.1,4.2.2
kube-bench run --targets master --check 1.1.11,1.1.12
```

Each FAIL has a **remediation** section at the bottom of the output. Reading it is the fastest way to get the file path and the fix.

Exit the node with `exit` (twice).

---

## 4. Answers

<details>
<summary>Click to reveal. Try it first!</summary>

### Where things live on this node

| What | Path |
|---|---|
| kubelet config file | `/var/lib/kubelet/config.yaml` |
| kubelet systemd flags | `/etc/systemd/system/kubelet.service.d/10-kubeadm.conf` (only `--config=...` here, so fix the **config file**) |
| etcd static pod | `/etc/kubernetes/manifests/etcd.yaml` |
| etcd data dir | `/var/lib/minikube/etcd` (find it with `ps -ef \| grep etcd` → `--data-dir`; on a normal kubeadm exam node it's `/var/lib/etcd`) |

### A. kubelet: CIS 4.2.1 and 4.2.2

```bash
vi /var/lib/kubelet/config.yaml
```

```yaml
authentication:
  anonymous:
    enabled: false      # was true
...
authorization:
  mode: Webhook         # was AlwaysAllow
```

```bash
systemctl daemon-reload
systemctl restart kubelet
systemctl status kubelet --no-pager | head -5
```

If the exam node passes them as **flags** in the systemd drop-in instead, set `--anonymous-auth=false --authorization-mode=Webhook` there. Flags override the config file.

### B. etcd flags: CIS 2.2, 2.3, 2.6

```bash
vi /etc/kubernetes/manifests/etcd.yaml
```

```yaml
    - --client-cert-auth=true      # was false
    # delete these two lines (or set them to false)
    # - --auto-tls=true
    # - --peer-auto-tls=true
```

Save it and the kubelet restarts etcd on its own. Don't leave a backup copy inside `/etc/kubernetes/manifests/`, or the kubelet will try to run it too.

#### If the apiserver dies after editing etcd.yaml

The apiserver log shows `dial tcp 127.0.0.1:2379: connection refused`, which means **etcd is down**, not the apiserver. Read etcd's own log:

```bash
docker ps -a | grep etcd                 # exam nodes: crictl ps -a | grep etcd
docker logs <exited-etcd-container-id>   # exam nodes: crictl logs <id>
# or: ls /var/log/pods/kube-system_etcd-*/etcd/ ; tail the newest .log
```

Classic mistakes:
- `--client-cert-auth="true"` gives `invalid boolean value "\"true\""`. Never put quotes around flag values in a manifest's `command:` list.
- The same flag twice (an old `=false` line left in plus a new `=true` line). **Edit the line that's there, don't add a new one.**
- After you fix etcd, the apiserver can stay down for up to ~5 min. It crashed while etcd was down, and the kubelet waits longer between each restart (CrashLoopBackOff). To bring it back immediately, run `docker ps -a | grep apiserver` and then `docker rm -f <exited-id>`, or just wait.
- A vim swap file such as `.etcd.yaml.swp` left in `/etc/kubernetes/manifests/` after a crashed vim. It's harmless (the kubelet skips dotfiles), but delete it.

### C. etcd data dir: CIS 1.1.11 and 1.1.12

```bash
ps -ef | grep etcd | grep -o -- '--data-dir=[^ ]*'    # -> /var/lib/minikube/etcd
id etcd                                               # no such user
useradd -r -s /usr/sbin/nologin etcd                  # system user, no login
chown -R etcd:etcd /var/lib/minikube/etcd
chmod 700 /var/lib/minikube/etcd
```

### D. Verify

```bash
kube-bench run --targets master,etcd,node | grep -E " (1\.1\.1[12]|2\.[236]|4\.2\.[12]) "
```

All 7 should be `[PASS]`. Then check the cluster still works (the etcd and apiserver restart takes ~30–60s):

```bash
exit; exit
```

```powershell
kubectl --context cks-q01 get pods -n kube-system
kubectl --context cks-q01 get nodes
```

The solution fragments are also in [`yaml/solution-kubelet-config.yaml`](yaml/solution-kubelet-config.yaml) and [`yaml/solution-etcd-flags.yaml`](yaml/solution-etcd-flags.yaml).

</details>

---

## 5. Optional: run kube-bench as a Job (YAML)

This is what you'd do without SSH. It's tested on this node.

```powershell
kubectl --context cks-q01 apply -f yaml/kube-bench-job.yaml
kubectl --context cks-q01 wait --for=condition=complete job/kube-bench --timeout=120s
kubectl --context cks-q01 logs job/kube-bench | Select-String "FAIL"
kubectl --context cks-q01 delete job kube-bench
```

---

## 6. Retry from scratch

Delete and set up again (section 7, then section 1). It takes about 3 minutes.

## 7. Delete the node (do this before the next question)

```powershell
.\cleanup.ps1
```

or

```powershell
minikube delete -p cks-q01
```

Setup uses `--keep-context`, so your current kubectl context is never switched. Always pass `--context cks-q01`.

---

## Files

```
01-kubelet-etcd-kube-bench/
  README.md                      this file
  setup.ps1                      start node + break it
  cleanup.ps1                    delete node
  setup/break-node.sh            runs inside the node: installs kube-bench, makes kubelet/etcd insecure
  yaml/kube-bench-job.yaml       kube-bench as a Job (minikube paths)
  yaml/solution-kubelet-config.yaml
  yaml/solution-etcd-flags.yaml
```

Refs: [kube-bench](https://github.com/aquasecurity/kube-bench) · [Kubelet authn/authz](https://kubernetes.io/docs/reference/access-authn-authz/kubelet-authn-authz/) · [Operating etcd](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/)
