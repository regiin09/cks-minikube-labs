# Q03 — Falco: Pod accessing /dev/mem

Practice scenario: write a custom Falco rule, identify the Pod that reads `/dev/mem`, and scale its Deployment to 0.

| | |
|---|---|
| Domain | Monitoring, Logging and Runtime Security |
| Node | 1 × minikube `cks-q03` (2 CPU, 2 GB RAM, Docker driver, docker runtime) |
| Falco | 0.45.x, installed on the node as systemd service `falco-modern-bpf` (modern eBPF) |
| Workloads | namespace `ai`: Deployments `nvidia`, `cpu`, `ollama`. **One of them, picked at random each setup, reads `/dev/mem`** |
| Grader | `.\check.ps1`: 14 checks |
| Target time | **10 minutes** |

> ⚠️ Every `kubectl` command here uses `--context cks-q03`. Setup uses `--keep-context`, so your current context isn't switched.

---

## 1. Get ready (setup)

```powershell
cd 03-falco-dev-mem
.\setup.ps1
```

This takes ~3 minutes (installs Falco from the Falco apt repo) and ends with `Ready. Start your timer…`. Check:

```powershell
kubectl --context cks-q03 -n ai get deploy        # nvidia, cpu, ollama all 1/1
.\check.ps1                                       # starts at 4 / 14
```

---

## 2. The task (start the timer)

> A Pod in namespace `ai` is reading raw host memory through `/dev/mem`. Falco is installed on node `cks-q03` (systemd unit `falco-modern-bpf`).
>
> 1. In `/etc/falco/falco_rules.local.yaml` create a Falco rule named **`Pod accessing /dev/mem`** that:
>    - fires when **any process inside a container** opens `/dev/mem`
>    - has priority **`WARNING`**
>    - has output in **exactly** this format:
>      `%evt.time,%container.id,%k8s.ns.name,%k8s.pod.name,%proc.name`
> 2. Configure Falco to also write alerts to the file **`/opt/course/03/falco.log`**. Make sure alerts are actually being generated.
> 3. Using Falco, identify the offending Pod. Write it to **`/opt/course/03/pod.txt`** in the format `<namespace>/<pod-name>`.
> 4. Scale the Deployment that owns that Pod to **0** replicas. Do not delete it and do not touch the other Deployments.
>
> 💡 If you have trouble getting Falco to log, check that the output channel and minimum **priority** let your alert through (syslog/stdout, priority `debug`). Alternatively, run Falco directly from the command line, bypassing systemd.

Don't read the Deployment YAML to cheat. The commands are base64 on purpose. Practise the Falco path.

---

## 3. Log in to the node

```powershell
minikube -p cks-q03 ssh --native-ssh=false
sudo -i
```

On the node, as root, `kubectl` and `k` work with **Tab completion**, plus `$do` (= `--dry-run=client -o yaml`).

Done? `exit` twice, then `.\check.ps1`.

---

## 4. Answers

<details>
<summary>Click to reveal. Try it first!</summary>

### 1. The rule

```bash
vi /etc/falco/falco_rules.local.yaml
```

```yaml
- rule: Pod accessing /dev/mem
  desc: A process inside a container opened /dev/mem
  condition: >
    evt.type in (open, openat, openat2)
    and fd.name = /dev/mem
    and container.id != host
  output: "%evt.time,%container.id,%k8s.ns.name,%k8s.pod.name,%proc.name"
  priority: WARNING
```

- `container.id != host` = "inside a container". The default macro `container` does the same, so `and container` also works.
- Quote the `output:` string. A bare `%` at the start of a YAML value is invalid YAML.
- Validate before restarting:
  ```bash
  falco -V /etc/falco/falco_rules.yaml -V /etc/falco/falco_rules.local.yaml
  ```

Don't remember field names? On the exam you can open the allowed docs: **falco.org → Supported Fields for Conditions and Outputs**. Or on the node: `falco --list | grep -E '^(fd\.name|k8s\.pod|container\.id)'`.

### 2. Make Falco actually log (the hidden trap)

Setup left `priority: error` in `/etc/falco/falco.yaml`. That's the **minimum** priority Falco emits, so your `WARNING` alerts are silently dropped.

```bash
vi /etc/falco/falco.yaml
```

```yaml
priority: debug            # was: error

file_output:
  enabled: true            # was: false
  keep_alive: false
  filename: /opt/course/03/falco.log

syslog_output:
  enabled: true            # already true here. On the exam, check it.
stdout_output:
  enabled: true
```

```bash
systemctl restart falco-modern-bpf
journalctl -fu falco-modern-bpf | grep /dev/mem     # or: grep Warning
tail -f /opt/course/03/falco.log
```

Within ~10s you'll see something like:

```
08:13:34.39: Warning 08:13:34.39,b770d6d79f33,ai,nvidia-7464fb9ff7-nkglz,dd container_id=...
```

The fields are `time, container id, namespace, POD, process`. Falco 0.4x also appends `container_id=… k8s_pod_name=…`. That's fine, your format is the part before them.

**Plan B: run Falco in the foreground, bypassing systemd** (prints alerts to your terminal):

```bash
falco -o engine.kind=modern_ebpf          # Ctrl+C to stop. Add  -o priority=debug  to override the config
# or with only your rules file:
falco -o engine.kind=modern_ebpf -r /etc/falco/falco_rules.local.yaml
```

### 3. Record the pod

```bash
echo "ai/nvidia-7464fb9ff7-nkglz" > /opt/course/03/pod.txt      # use YOUR pod name from the alert
```

You can also map a container id to a pod: `docker ps | grep b770d6d79f33` (exam: `crictl ps -id b770d6d79f33` / `crictl inspect`).

### 4. Scale its Deployment to 0

```bash
k -n ai get pod nvidia-7464fb9ff7-nkglz -o jsonpath='{.metadata.ownerReferences[0].name}'   # ReplicaSet
k -n ai scale deploy nvidia --replicas=0
k -n ai get deploy
```

(Pod name minus the last two `-xxxxx` parts = the Deployment name.) Don't `kubectl delete` the pod: the ReplicaSet just recreates it.

Full rule file: [`solution/falco_rules.local.yaml`](solution/falco_rules.local.yaml).

</details>

---

## 5. Retry from scratch

`.\cleanup.ps1` then `.\setup.ps1`. A **different Deployment may be the bad one** next time.

## 6. Delete the node (before the next question)

```powershell
.\cleanup.ps1
```

or `minikube delete -p cks-q03`.

---

## Notes on this lab vs the exam

- minikube nodes share Docker Desktop's single WSL2 kernel. Falco on `cks-q03` sees syscalls from **every** container on your PC (other minikube nodes too). Only events from `cks-q03`'s own pods get `k8s.pod.name` filled in. You won't notice this unless another lab also touches `/dev/mem`.
- Exam nodes usually run containerd: use `crictl` instead of `docker`.

## Files

```
03-falco-dev-mem/
  README.md
  setup.ps1                      start node, install Falco, break priority, deploy 3 workloads (1 random bad)
  check.ps1                      grader (14 checks)
  cleanup.ps1                    delete node
  setup/break-node.sh            runs on node: Falco install + priority: error
  setup/check.sh                 grader logic (runs on node)
  yaml/workloads.yaml            template for nvidia / cpu / ollama
  solution/falco_rules.local.yaml
```

Refs: [Falco rules basics](https://falco.org/docs/concepts/rules/basic-elements/) · [Supported fields](https://falco.org/docs/reference/rules/supported-fields/) · [Falco outputs / channels](https://falco.org/docs/concepts/outputs/channels/) · [Install Falco (deb)](https://falco.org/docs/setup/packages/)
