# Q09 — Create the missing TLS Secret for a Deployment

Practice scenario: create the TLS Secret that a Deployment already references.

| | |
|---|---|
| Domain | Cluster Setup / Minimize microservice vulnerabilities (Secrets) |
| Node | 1 × minikube `cks-q09` (2 CPU, 2 GB RAM) |
| Workload | namespace `secure`, Deployment `web` (nginx serving HTTPS on 443), Service `web`. The pod mounts a TLS Secret that **does not exist**, so it hangs in `ContainerCreating` |
| Random each setup | the **Secret name** the Deployment references |
| Grader | `.\check.ps1`: 9 checks |
| Target time | **4 minutes** |

> ⚠️ From Windows, always pass `--context cks-q09`. Never drop it: your kubeconfig may also contain real clusters.

---

## 1. Get ready (setup)

```powershell
cd 09-tls-secret
.\setup.ps1
```

This takes ~2 minutes and ends with `Ready. Start your timer…`. The grader starts at `1 / 9` (only "Deployment unchanged" passes):

```powershell
.\check.ps1
```

---

## 2. The task (start the timer)

> Deployment **`web`** in namespace **`secure`** references a TLS Secret that does not exist, so its Pods cannot start.
>
> Create that Secret in namespace `secure`, of type **`kubernetes.io/tls`**, using the certificate **`/opt/course/09/web.pem`** and the private key **`/opt/course/09/web-key.pem`**.
>
> Do **not** modify the Deployment. Make sure the Pods of Deployment `web` are Running and serve HTTPS with that certificate.

---

## 3. Log in

```powershell
minikube -p cks-q09 ssh --native-ssh=false
sudo -i
```

You have `k` / `kubectl` with Tab and `$do`. Done? `exit` twice, then `.\check.ps1`.

---

## 4. Answers

<details>
<summary>Click to reveal. Try it first!</summary>

### 1. Find the Secret name

```bash
k -n secure get deploy web -o yaml | grep -A3 secretName
k -n secure get deploy web -o jsonpath='{.spec.template.spec.volumes[*].secret.secretName}'; echo
k -n secure describe pod -l app=web | grep -A5 Events      # FailedMount ... secret "<name>" not found
```

### 2. Which file is which?

```bash
head -1 /opt/course/09/web.pem       # -----BEGIN CERTIFICATE-----   -> --cert
head -1 /opt/course/09/web-key.pem   # -----BEGIN PRIVATE KEY-----   -> --key
```

### 3. Create it

```bash
k -n secure create secret tls <name> --cert=/opt/course/09/web.pem --key=/opt/course/09/web-key.pem
k -n secure get secret <name>        # TYPE kubernetes.io/tls, DATA 2
```

### 4. Pods come up

The kubelet retries the mount on its own (backoff, up to ~2 min). To speed it up, delete the pod. The ReplicaSet recreates it with the **unchanged** template:

```bash
k -n secure delete pod -l app=web
k -n secure rollout status deploy/web
```

### 5. Verify HTTPS

```bash
IP=$(k -n secure get svc web -o jsonpath={.spec.clusterIP})
curl --cacert /opt/course/09/web.pem --resolve web.secure.svc:443:$IP https://web.secure.svc/   # secure web OK
echo | openssl s_client -connect $IP:443 2>/dev/null | openssl x509 -noout -fingerprint -sha256
openssl x509 -in /opt/course/09/web.pem -noout -fingerprint -sha256                             # same
```

Scripted version: [`solution/solve.sh`](solution/solve.sh).

</details>

---

## Traps

| Trap | What happens |
|---|---|
| `create secret generic <name> --from-file=web.pem --from-file=web-key.pem` | Wrong **type** (`Opaque`) and wrong **key names** (`web.pem`, not `tls.crt`). nginx can't find `/etc/nginx/tls/tls.crt` and crashes. |
| `create secret generic --from-file=tls.crt=web.pem --from-file=tls.key=web-key.pem` | The pod even works, but the type is `Opaque`, not `kubernetes.io/tls`. The grader fails it (tested: 8/9). |
| `--cert` and `--key` swapped | kubectl refuses: `tls: failed to find certificate PEM data ... PEM inputs may have been switched`. Check `head -1` of each file. |
| Forgetting `-n secure` | The Secret lands in `default`; the pod still says `secret ... not found`. |
| Guessing the name (`web-tls`) | The name is random each setup. Read it from the Deployment or the FailedMount event. |
| Editing the Deployment to point at your own Secret name | Forbidden by the task. The grader hashes the pod template (`kubectl rollout restart` is fine; it only adds an annotation). |
| Waiting forever | The mount retry backs off. `k delete pod` is the quick fix. |

---

## 5. Retry from scratch

`.\cleanup.ps1` then `.\setup.ps1`. The Secret name changes each time.

## 6. Delete the node (before the next question)

```powershell
.\cleanup.ps1
```

---

## Files

```
09-tls-secret/
  README.md
  setup.ps1              node, node tools, cert/key, Deployment with missing Secret
  check.ps1              grader (9 checks)
  cleanup.ps1            delete node
  setup/break-node.sh    runs on node: openssl cert+key, random Secret name, apply yaml, grader key
  setup/check.sh         grader logic (Secret type/keys/fingerprints, template hash, live HTTPS)
  yaml/web.yaml          namespace, nginx TLS ConfigMap, Deployment, Service (template)
  solution/solve.sh      scripted solution
```

Refs: [TLS Secrets](https://kubernetes.io/docs/concepts/configuration/secret/#tls-secrets) · [kubectl create secret tls](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_create/kubectl_create_secret_tls/) · [Secret volumes](https://kubernetes.io/docs/concepts/storage/volumes/#secret)
