# How every lab is built (contributor guide)

Read this before adding a new lab. Use `02-docker-daemon-dockerfile`, `05-sbom-libcrypto3` and `07-imagepolicywebhook` as templates: copy their structure and style.

## Purpose
Each lab is a practice scenario for one CKS curriculum topic, running on a local minikube node. You time yourself solving it, then grade it with `.\check.ps1`. Write scenarios in your own words. Don't copy real exam questions: they are covered by the Linux Foundation's confidentiality terms.

## Folder layout (`EXAM_ENV/NN-short-name/`)
```
README.md            table, setup, task (exam wording), login, answers in <details>, traps table, retry, delete, files, refs
setup.ps1            builds everything; ends "Ready. Start your timer, then:  minikube -p cks-qNN ssh --native-ssh=false"
check.ps1            copies setup/check.sh to the node and runs it with "sudo -i bash", then "sudo rm" it
cleanup.ps1          minikube delete -p cks-qNN ; minikube profile list
setup/break-node.sh  runs ON the node as root: creates the starting (broken/incomplete) state
setup/check.sh       grader: PASS/FAIL per item + "Score: x / y"
yaml/                manifests (starting state)
solution/            solution files and/or solve.sh (used to test the grader)
```

## Hard rules
- Profile name is `cks-qNN`. **Never touch other profiles** (several labs may run at the same time). **Never change the kubectl current-context.** Pass `--keep-context` to minikube start and `--context cks-qNN` to every kubectl call from the host. A learner's kubeconfig may contain real clusters, and a lab must never be able to touch them.
- Use minimal resources: `--nodes=1 --cpus=2 --memory=2048`, unless the lab really needs more.
- Always pass `--driver=docker --container-runtime=docker`.
- After the node is built, every setup.ps1 must run `../_common/node-tools.sh` on the node. It sets up kubectl on the PATH for root, `k`, Tab completion, `$do`, and the vim arrow-key fix.
- Grade both the persistent config and live behaviour. A temporary fix that a restart would undo should FAIL.
- Where you can, randomise the answer in each setup (shuffle which item is the "bad" one, as in 03 and 05) so the answer can't be memorised.
- Never back up files inside `/etc/kubernetes/manifests/`. Static pod volume names must be RFC 1123 (`a-z0-9-`, no `_`).

## Windows / tooling gotchas (all hit before)
- PowerShell 5.1: don't use `$ErrorActionPreference="Stop"` with minikube, because its stderr warnings abort the script. Use the `Step { ... }` helper that checks `$LASTEXITCODE` (see 02/setup.ps1).
- Git Bash: prefix commands with `export MSYS_NO_PATHCONV=1`, or `/tmp/...` gets rewritten to `C:/Program Files/Git/tmp`.
- `minikube cp` with an absolute `C:\...` source reads `C` as a node name. `cd` into the folder and use a relative path.
- Files that `minikube cp` puts in `/tmp` may be root-owned, so delete them with `sudo rm`.
- With `set -o pipefail`, `cmd | head` exits 141 (SIGPIPE). Don't pipe into `head` in setup scripts.
- `rollout status` takes one resource. For several, use `kubectl wait --for=condition=available deploy --all`.
- Quote `%` at the start of YAML values.
- Use `kubectl` (not python) to edit live objects. python3 and openssl are on the node; jq is not.
- minikube layout: certs are in `/var/lib/minikube/certs`, etcd data in `/var/lib/minikube/etcd`, kubelet config in `/var/lib/kubelet/config.yaml`, static pods in `/etc/kubernetes/manifests`. The kubelet unit drop-in is `/etc/systemd/system/kubelet.service.d/10-kubeadm.conf`. Node user is `docker` with passwordless sudo.
- Pods that start before a CNI is installed get minikube's bridge IPs. Restart them after installing the CNI.

## Required testing before you report done
1. Build from scratch with `.\setup.ps1` (delete your profile first).
2. Run `.\check.ps1`: the starting state must score LOW.
3. Run the node-shell check: `cd _common; minikube -p cks-qNN cp verify-node.sh cks-qNN:/tmp/verify-node.sh; minikube -p cks-qNN ssh -- "bash /tmp/verify-node.sh"`. It must be 9/9.
4. Apply the solution the way a person would by hand, then run `.\check.ps1`: it must be FULL marks.
5. Negative test: at least one plausible WRONG answer must FAIL the relevant check.
6. `minikube delete -p cks-qNN` at the end.
