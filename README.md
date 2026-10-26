# CKS minikube labs

![labs](https://img.shields.io/badge/labs-16-blue) ![kubernetes](https://img.shields.io/badge/kubernetes-v1.35-326ce5?logo=kubernetes&logoColor=white) ![minikube](https://img.shields.io/badge/minikube-v1.38%2B-f7931e) ![license](https://img.shields.io/badge/license-MIT-green)

Hands-on practice labs for the **Certified Kubernetes Security Specialist (CKS)** exam, running on your own machine with **minikube**.

Each lab builds a fresh cluster and **breaks it on purpose**. You fix it under a timer, like on the exam, and then a **grader** checks your work: the config files *and* what actually happens in the cluster.

- 16 labs covering every CKS domain: cluster setup, cluster hardening, system hardening, microservice vulnerabilities, supply chain, runtime security
- Real tools installed for you: kube-bench, Falco, bom, Cilium (with SPIRE mutual auth), Istio, Calico, ingress-nginx, an ImagePolicyWebhook backend
- Some labs **randomise the answer** on every setup, so you can't memorise it
- Every lab has the answers (hidden until you click) and a **traps** table: the mistakes that cost points, each one checked on a real cluster

> **Disclaimer:** not affiliated with or endorsed by the Linux Foundation or CNCF. These are original practice scenarios for the public [CKS curriculum](https://github.com/cncf/curriculum), not real exam questions.

---

## Requirements

| | |
|---|---|
| Docker | Docker Desktop (Windows/macOS) or Docker Engine (Linux), running |
| [minikube](https://minikube.sigs.k8s.io/docs/start/) | v1.38 or newer |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | any recent version |
| PowerShell | Windows: built in. **macOS/Linux:** install [PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell) and run the scripts with `pwsh` |
| [helm](https://helm.sh/docs/intro/install/) | only for labs 06 and 16 |
| RAM | 2–3 GB free **per running lab** (8 GB+ machine recommended) |
| Internet | setup pulls images and packages (Falco, kube-bench, Istio and others) |

**Tested on:** Windows 11, Docker Desktop (WSL2), minikube v1.38.1, Kubernetes v1.35.1. The scripts are written to work with `pwsh` on macOS/Linux too, but that hasn't been tested yet. Reports and PRs are welcome.

---

## Quick start

```powershell
git clone https://github.com/regiin09/cks-minikube-labs.git
cd cks-minikube-labs/03-falco-dev-mem

./setup.ps1                                   # 2–8 min: builds the node and breaks it. Then start your timer
minikube -p cks-q03 ssh --native-ssh=false    # log in to the node ...
sudo -i                                       # ... and become root, like on the exam
# read the task in README.md and solve it on the node (k, kubectl, Tab completion, vim all ready)
exit; exit
./check.ps1                                   # grade yourself: PASS/FAIL per item + score
./cleanup.ps1                                 # delete the node before the next lab
```

On macOS/Linux, run `pwsh ./setup.ps1` (and likewise for the other scripts).

**Windows: "running scripts is disabled on this system"?** Run this once in the same window:
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```
If the files came from a zip download, also run `Get-ChildItem -Recurse *.ps1 | Unblock-File`.

---

## The labs

| # | Lab | What you do | Domain | Node(s) | Target |
|---|---|---|---|---|---|
| 01 | [kubelet-etcd-kube-bench](01-kubelet-etcd-kube-bench/) | Fix kubelet + etcd CIS findings with kube-bench | Cluster Setup | 1 × 2 GB | 8 min |
| 02 | [docker-daemon-dockerfile](02-docker-daemon-dockerfile/) | Lock down dockerd (TCP 2375, socket, docker group); fix a Dockerfile + Deployment | System Hardening / Microservices | 1 × 2 GB | 13 min |
| 03 | [falco-dev-mem](03-falco-dev-mem/) | Custom Falco rule, find the Pod reading `/dev/mem`, scale it to 0 | Runtime Security | 1 × 2 GB | 10 min |
| 04 | [upgrade-worker-node](04-upgrade-worker-node/) | kubeadm worker upgrade: drain, apt, `kubeadm upgrade node`, uncordon | Cluster Hardening | 2 × 2 GB | 8 min |
| 05 | [sbom-libcrypto3](05-sbom-libcrypto3/) | Find the image with a given libcrypto3, SPDX SBOM with `bom`, remove the container | Supply Chain | 1 × 2 GB | 8 min |
| 06 | [cilium-network-policy](06-cilium-network-policy/) | CiliumNetworkPolicy: mutual auth, `host` entity, `egressDeny` | Cluster Setup / Microservices | 1 × 3 GB | 12 min |
| 07 | [imagepolicywebhook](07-imagepolicywebhook/) | Finish an ImagePolicyWebhook setup, fail closed | Supply Chain | 1 × 2 GB | 10 min |
| 08 | [istio-mtls](08-istio-mtls/) | Sidecar injection + PeerAuthentication STRICT | Microservices | 1 × 3 GB | 6 min |
| 09 | [tls-secret](09-tls-secret/) | Create the TLS Secret a Deployment is waiting for | Microservices | 1 × 2 GB | 4 min |
| 10 | [audit-logging](10-audit-logging/) | Enable API server auditing, policy rule order, retention | Runtime Security | 1 × 2 GB | 10 min |
| 11 | [networkpolicy](11-networkpolicy/) | Default-deny ingress + allow from one namespace | Cluster Setup | 1 × 2 GB | 6 min |
| 12 | [ingress-tls](12-ingress-tls/) | ingress-nginx Ingress with TLS + HTTP→HTTPS redirect | Cluster Setup | 1 × 2 GB | 6 min |
| 13 | [sa-projected-token](13-sa-projected-token/) | Disable SA token automount, mount a projected token read-only | Cluster Hardening | 1 × 2 GB | 6 min |
| 14 | [pss-restricted](14-pss-restricted/) | Make a Deployment pass the `restricted` Pod Security Standard | Microservices | 1 × 2 GB | 6 min |
| 15 | [apiserver-auth](15-apiserver-auth/) | No anonymous access, `Node,RBAC`, NodeRestriction | Cluster Hardening | 1 × 2 GB | 8 min |
| 16 | [cilium-ingress](16-cilium-ingress/) | Cilium Ingress controller with TLS + HTTPS redirect | Cluster Setup | 1 × 2 GB | 6 min |

The target time is roughly what the task would be worth on a 2-hour exam. If you go over, practise it again.

---

## How a lab works

```
NN-name/
  README.md         the task (start the timer when you read it), how to log in, answers (hidden), traps
  setup.ps1         creates minikube profile cks-qNN, installs tools, puts the cluster in the broken state
  check.ps1         grader. Re-run it as often as you like
  cleanup.ps1       deletes the node
  setup/            scripts that run inside the node (break, grade)
  yaml/             starting manifests
  solution/         the model answer (try first!)
```

- **The node feels like an exam node.** After `sudo -i` you have `kubectl`, `k` with Tab completion, `$do` (`--dry-run=client -o yaml`), and vim with working arrow keys.
- **Retry:** `./cleanup.ps1` then `./setup.ps1`. Where the answer is randomised, you'll get a different one.
- **Several labs at once** is fine. Each uses its own profile (`cks-q01` … `cks-q16`).

---

## Safety

- Setup **never changes your current kubectl context** (`minikube start --keep-context`), and every command passes `--context cks-qNN`. If your kubeconfig has real clusters, the labs can't reach them. Still, glance at `kubectl config current-context` before running anything by hand.
- Everything happens inside throwaway minikube containers. Some labs deliberately make the node insecure (for example lab 02 opens an unauthenticated Docker API *inside* the node), so don't expose minikube to a network you don't trust.
- `cleanup.ps1` removes the whole node.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| Arrow keys print `^[[A` in the node | Log in with `minikube -p cks-qNN ssh --native-ssh=false` (minikube's built-in SSH client on Windows doesn't pass arrow keys) |
| Git Bash rewrites `/tmp/...` into `C:/Program Files/Git/tmp` | Run the PowerShell scripts from PowerShell, or `export MSYS_NO_PATHCONV=1` |
| Setup fails pulling images (quay.io, docker.io) | Usually a network blip. Run `./cleanup.ps1` then `./setup.ps1` again |
| API server doesn't come back after you edit its manifest | `journalctl -u kubelet \| grep "Could not process manifest"` on the node, and `docker ps -a \| grep apiserver`. Never keep backups inside `/etc/kubernetes/manifests/` |
| Out of memory / nodes very slow | Run fewer labs at once. `minikube profile list`, then `./cleanup.ps1` in the labs you're done with |

---

## Contributing

New labs and fixes are welcome. Read [`_common/LAB-CONVENTIONS.md`](_common/LAB-CONVENTIONS.md) first. Every lab must be tested from scratch: low score at the start, full score with the solution, a wrong answer that fails, and 9/9 on [`_common/verify-node.sh`](_common/verify-node.sh). Write scenarios in your own words; don't post real exam questions.

## License

[MIT](LICENSE)
