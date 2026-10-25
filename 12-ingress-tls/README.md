# Q12 — Expose HTTPS via Ingress (TLS termination + ssl-redirect)

Practice scenario: expose an app over HTTPS with an ingress-nginx Ingress, TLS termination and an HTTP to HTTPS redirect.

| | |
|---|---|
| Domain | Cluster Setup (Ingress with TLS) |
| Node | 1 × minikube `cks-q12` (2 CPU, 2 GB RAM) |
| Ingress controller | **ingress-nginx** (minikube addon), IngressClass **`nginx`** |
| Workload | namespace `web`: Deployment + Service **`web-app`** (HTTP on 80). Also a decoy Secret `web-tls-old` (cert for `old.example.local`) |
| Files | `/opt/course/12/tls.crt`, `/opt/course/12/tls.key` (self-signed, SAN `secure.example.local`, new each setup) |
| Grader | `.\check.ps1`: 9 checks, the **spec AND real traffic** (redirect, 200, which cert is served) |
| Target time | **6 minutes** |

---

## 1. Get ready (setup)

```powershell
cd 12-ingress-tls
.\setup.ps1
```

This takes ~3 minutes and ends with `Ready. Start your timer…`. The grader starts at `0 / 9`:

```powershell
.\check.ps1
```

---

## 2. The task (start the timer)

> A Deployment and Service **`web-app`** (port 80) run in namespace **`web`**. A certificate and key for host **`secure.example.local`** are at `/opt/course/12/tls.crt` and `/opt/course/12/tls.key`.
>
> 1. Create a TLS Secret **`secure-tls`** in namespace `web` from these files.
> 2. Create an Ingress **`secure-ingress`** in namespace `web`:
>    - ingressClassName **`nginx`**
>    - host **`secure.example.local`**, path **`/`** (pathType **Prefix**) → Service **`web-app:80`**
>    - TLS for that host using Secret `secure-tls`
>    - HTTP must be redirected to HTTPS: annotation **`nginx.ingress.kubernetes.io/ssl-redirect: "true"`**

---

## 3. Log in

```powershell
minikube -p cks-q12 ssh --native-ssh=false
sudo -i
```

You have `k`/`kubectl` with Tab, `curl` and `openssl`. Done? `exit` twice, then `.\check.ps1`.

Test it yourself from the node (there is no DNS for the host, so send the Host header / use `--resolve`):

```bash
IP=$(k -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.spec.clusterIP}')
curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' -H 'Host: secure.example.local' http://$IP   # 308 https://secure.example.local/
curl -sk --resolve secure.example.local:443:$IP https://secure.example.local                        # Q12 web-app: hello ...
echo | openssl s_client -connect $IP:443 -servername secure.example.local 2>/dev/null | openssl x509 -noout -subject -ext subjectAltName
#  subject=CN = secure.example.local, O = cks-q12        <- good
#  subject=O = Acme Co, CN = Kubernetes Ingress Controller Fake Certificate   <- your TLS is NOT used
```

---

## 4. Answers

<details>
<summary>Click to reveal. Try it first!</summary>

### Fast way: two imperative commands

```bash
k -n web create secret tls secure-tls --cert=/opt/course/12/tls.crt --key=/opt/course/12/tls.key

k -n web create ingress secure-ingress --class=nginx \
  --rule="secure.example.local/*=web-app:80,tls=secure-tls" \
  --annotation=nginx.ingress.kubernetes.io/ssl-redirect=true

k -n web get ing secure-ingress            # PORTS 80, 443
k -n web describe ing secure-ingress       # TLS: secure-tls terminates secure.example.local
```

> ⚠️ **`/*`, not `/`.** In `kubectl create ingress`, `host/path*` gives `pathType: Prefix`; `host/path` without `*` gives **`Exact`**. The task said Prefix.
> `,tls=secure-tls` adds the `tls:` block with the rule's host. `--annotation=key=true` is stored as the string `"true"`, so no quoting problem here.

### YAML way

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: secure-ingress
  namespace: web
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"     # a STRING, quoted
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - secure.example.local                               # must match the rule host
    secretName: secure-tls                               # same namespace as the Ingress
  rules:
  - host: secure.example.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-app
            port:
              number: 80
```

```bash
k -n web create ingress secure-ingress --class=nginx --rule="secure.example.local/*=web-app:80,tls=secure-tls" $do > ing.yaml
# add the annotation, then
k apply -f ing.yaml
```

Files: [`solution/solve.sh`](solution/solve.sh), [`solution/ingress.yaml`](solution/ingress.yaml).

### Traps (each one was verified in this lab)

| Trap | What actually happens |
|---|---|
| `ssl-redirect: true` (no quotes) in YAML | `kubectl apply` refuses it: `cannot unmarshal bool into … annotations of type string`. Annotation values are always strings: `"true"`. |
| No `tls:` block | HTTPS still answers, but with the controller's **"Kubernetes Ingress Controller Fake Certificate"**, and HTTP is **not** redirected (no 308). Grader: 6/9. |
| Wrong Secret (e.g. the decoy `web-tls-old`) | The cert doesn't match `secure.example.local`, so nginx serves the **Fake Certificate**. Redirect and 200 still work, so it looks fine unless you check the cert. Grader: 7/9. |
| `tls.hosts` doesn't match the rule host | Same: no cert for that SNI name, the Fake Certificate is served. |
| Secret in another namespace | An Ingress can only use a Secret in **its own** namespace. Otherwise: Fake Certificate. |
| `ingressClassName` missing | In this lab the minikube `nginx` class is marked `is-default-class`, so the API server fills it in for you. On the exam that may not be so: without a default class the controller **ignores** the Ingress (no ADDRESS). Always set `ingressClassName: nginx` / `--class=nginx`. |
| `--rule="host/=svc:80"` | pathType **Exact**, not Prefix. Use `host/*=svc:80`. |
| `kubectl create secret generic` | Type `Opaque` with your own key names. Use `create secret tls` → type `kubernetes.io/tls`, keys `tls.crt`/`tls.key`. |

> ingress-nginx already redirects HTTP→HTTPS by default for any host with TLS (`ssl-redirect` defaults to `true`). The annotation makes it explicit, and the task asks for it, so the grader checks it in the spec.

</details>

---

## 5. Retry from scratch

`k -n web delete ing secure-ingress; k -n web delete secret secure-tls` brings you back to the start state. Or `.\cleanup.ps1` then `.\setup.ps1` (new cert each time).

## 6. Delete the node (before the next question)

```powershell
.\cleanup.ps1
```

---

## Lab notes

- `minikube addons enable ingress` installs ingress-nginx v1.14 and IngressClass `nginx`. Setup waits for the admission jobs and the controller pod, because the validating webhook must be up before any Ingress can be created.
- The grader talks to the controller's ClusterIP from the node: `-H Host:` for HTTP, `--resolve` and `openssl s_client -servername` for HTTPS, and compares the served cert's SHA-256 fingerprint with `/opt/course/12/tls.crt`.

## Files

```
12-ingress-tls/
  README.md
  setup.ps1                 node, ingress addon (wait for webhook), node tools, certs, web-app
  check.ps1                 grader (9 checks: Secret + Ingress spec + live 308/200/cert)
  cleanup.ps1               delete node
  setup/break-node.sh       runs on node: cert+key in /opt/course/12, decoy Secret web-tls-old
  setup/check.sh            grader logic
  yaml/web-app.yaml         namespace web, ConfigMap page, Deployment + Service web-app
  solution/solve.sh         imperative solution
  solution/ingress.yaml     YAML solution
```

Refs: [Ingress TLS](https://kubernetes.io/docs/concepts/services-networking/ingress/#tls) · [kubectl create ingress](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_create/kubectl_create_ingress/) · [ingress-nginx TLS / ssl-redirect](https://kubernetes.github.io/ingress-nginx/user-guide/tls/#server-side-https-enforcement-through-redirect)
