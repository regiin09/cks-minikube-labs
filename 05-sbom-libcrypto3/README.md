# Q05 — SBOM: find the container with libcrypto3 3.1.4-r5, remove it

Practice scenario: find which container image ships a specific `libcrypto3` version, generate an SPDX SBOM with `bom`, and remove that container.

| | |
|---|---|
| Domain | Supply Chain Security (SBOM) |
| Node | 1 × minikube `cks-q05` (2 CPU, 2 GB RAM) |
| Tools on node | `bom` v0.8.0, `kubectl`/`k` with Tab completion |
| Workload | namespace `alpine`, Deployment `alpine`, **one Pod, 3 containers** `alpine-a/b/c` on `alpine:3.19.1`, `3.20.0`, `3.21.3`, **shuffled at random each setup** |
| Grader | `.\check.ps1`: 11 checks |
| Target time | **8 minutes** |

> Every one of those images contains `libcrypto3`, but only one has version **3.1.4-r5**. So you have to check the **version**, not just the package name.

---

## 1. Get ready (setup)

```powershell
cd 05-sbom-libcrypto3
.\setup.ps1
```

This takes ~2–3 minutes and ends with `Ready. Start your timer…`. The grader starts at `2 / 11`:

```powershell
.\check.ps1
```

---

## 2. The task (start the timer)

> Deployment **`alpine`** in namespace **`alpine`** runs three containers, each on a different version of the `alpine` image.
>
> 1. Find out which container's image contains package **`libcrypto3`** in version **`3.1.4-r5`**. Write that **container name** to `/opt/course/05/container.txt`.
> 2. Use **`bom`** to generate an SPDX document of **that image** in **tag-value** format, saved to `/opt/course/05/sbom.spdx`.
> 3. Remove that container from the Deployment. The manifest is at `/opt/course/05/alpine-deployment.yaml`: update the file **and** apply it. Do not change the other two containers.

---

## 3. Log in

```powershell
minikube -p cks-q05 ssh --native-ssh=false
sudo -i
```

You have `k` / `kubectl` with Tab, and `bom`. Done? `exit` twice, then `.\check.ps1`.

---

## 4. Answers

<details>
<summary>Click to reveal. Try it first!</summary>

### 1. Exec into each container and check the package

```bash
k -n alpine get deploy alpine -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{"  "}{.image}{"\n"}{end}'

k -n alpine exec deploy/alpine -c alpine-a -- apk info -v | grep libcrypto3
k -n alpine exec deploy/alpine -c alpine-b -- apk info -v | grep libcrypto3
k -n alpine exec deploy/alpine -c alpine-c -- apk info -v | grep libcrypto3
```

Output looks like this (the container order changes each setup):

```
libcrypto3-3.1.4-r5     <- this one   (alpine:3.19.1)
libcrypto3-3.3.3-r0                   (alpine:3.21.3)
libcrypto3-3.3.0-r2                   (alpine:3.20.0)
```

Or as a one-liner loop:

```bash
for c in alpine-a alpine-b alpine-c; do echo "$c: $(k -n alpine exec deploy/alpine -c $c -- apk info -v | grep ^libcrypto3)"; done
```

Then:

```bash
echo alpine-a > /opt/course/05/container.txt      # YOUR container name
```

> Other ways in: `apk list -I | grep libcrypto3`, `cat /lib/apk/db/installed | grep -A1 'P:libcrypto3'`. If the exam image has **no shell or apk**, use bom on the image instead (step 2) and grep the SPDX for the version.

### 2. SBOM with bom (tag-value)

```bash
bom generate --image alpine:3.19.1 --format tag-value --output /opt/course/05/sbom.spdx
grep -A10 '^PackageName: libcrypto3$' /opt/course/05/sbom.spdx | grep PackageVersion   # 3.1.4-r5
```

> ⚠️ **bom v0.8 writes JSON by default**, even when the file is named `.spdx`. Older versions defaulted to tag-value. If the task says **tag-value**, pass `--format tag-value`. Check with `head -3 sbom.spdx`: tag-value starts with `SPDXVersion: SPDX-2.3`, JSON starts with `{`.
>
> Use `--image-archive file.tar` if the image is a tarball, not in a registry. `bom document outline sbom.spdx` prints a readable tree.

### 3. Remove the container: manifest + cluster

```bash
vi /opt/course/05/alpine-deployment.yaml
```

Delete the whole `- name: alpine-a` block (its `name`, `image` and `command` lines). Keep the other two exactly as they are:

```yaml
      containers:
      - name: alpine-b
        image: alpine:3.21.3
        command: ["sleep", "infinity"]
      - name: alpine-c
        image: alpine:3.20.0
        command: ["sleep", "infinity"]
```

```bash
k apply -f /opt/course/05/alpine-deployment.yaml
k -n alpine rollout status deploy/alpine
k -n alpine get pod -o jsonpath='{.items[0].spec.containers[*].name}'   # alpine-b alpine-c
```

> `k edit deploy` also changes the cluster, but then the **file** is still wrong, and the task said to update the file. Edit the file and `apply`.

Scripted version: [`solution/solve.sh`](solution/solve.sh).

</details>

---

## 5. Retry from scratch

`.\cleanup.ps1` then `.\setup.ps1`. The bad container letter changes each time.

## 6. Delete the node (before the next question)

```powershell
.\cleanup.ps1
```

---

## Files

```
05-sbom-libcrypto3/
  README.md
  setup.ps1                      node, bom, shuffled Deployment, node tools
  check.ps1                      grader (11 checks)
  cleanup.ps1                    delete node
  setup/break-node.sh            runs on node: install bom, task files, pre-pull images
  setup/check.sh                 grader logic
  yaml/alpine-deployment.yaml    template (tags filled in by setup)
  solution/solve.sh              scripted solution
```

| Image | libcrypto3 |
|---|---|
| alpine:3.19.1 | **3.1.4-r5** ← target |
| alpine:3.20.0 | 3.3.0-r2 |
| alpine:3.21.3 | 3.3.3-r0 |

Refs: [kubernetes-sigs/bom](https://github.com/kubernetes-sigs/bom) · [SPDX spec](https://spdx.github.io/spdx-spec/v2.3/) · [kubectl exec](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_exec/)
