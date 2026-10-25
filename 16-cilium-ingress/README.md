# Q16 — Cilium Ingress with TLS + HTTP→HTTPS redirect

Practice scenario: the same idea as lab 12, but the controller is **Cilium's** built-in ingress (Envoy), not ingress-nginx, so the nginx annotation does nothing.

| | |
|---|---|
| Domain | Cluster Setup (Ingress with TLS) |
| Node | 1 × minikube `cks-q16` (2 CPU, 2 GB RAM) |
| CNI / Ingress | **Cilium 1.20.3** (Helm) with the **Cilium Ingress controller**, IngressClass **`cilium`**, shared mode, kube-proxy replacement |
| Workload | namespace `shop`: Deployment + Service **`shop-app`** (HTTP on 80). Also a decoy Secret `shop-tls-old` (cert for `old-shop.example.local`) |
| Files | `/opt/course/16/tls.crt`, `/opt/course/16/tls.key` (self-signed, SAN `shop.example.local`, new each setup) |
| Grader | `.\check.ps1`: 9 checks, the **spec AND real traffic** (redirect, 200, which cert is served) |
| Target time | **6 minutes** |
| Needs on your PC | `helm` (you have it) |

---

## 1. Get ready (setup)

```powershell
cd 16-cilium-ingress
.\setup.ps1
```

This takes ~6 minutes (it pre-pulls the Cilium images with retries, because quay.io lookups from Docker Desktop are sometimes flaky). It ends with `Ready. Start your timer…`. The grader starts at `0 / 9`:

```powershell
.\check.ps1
```

---

## 2. The task (start the timer)

> The Cilium ingress controller is installed (IngressClass **`cilium`**). A Deployment and Service **`shop-app`** (port 80) run in namespace **`shop`**. A certificate and key for host **`shop.example.local`** are at `/opt/course/16/tls.crt` and `/opt/course/16/tls.key`.
>
> 1. Create a TLS Secret **`shop-tls`** in namespace `shop` from these files.
> 2. Create an Ingress **`shop-ingress`** in namespace `shop`:
>    - ingressClassName **`cilium`**
>    - host **`shop.example.local`**, path **`/`** (pathType **Prefix**) → Service **`shop-app:80`**
>    - TLS for that host using Secret `shop-tls`
>    - HTTP requests must be **redirected to HTTPS**

---

## 3. Log in

```powershell
minikube -p cks-q16 ssh --native-ssh=false
sudo -i
```

You have `k`/`kubectl` with Tab, `curl` and `openssl`. Done? `exit` twice, then `.\check.ps1`.

### Where is the controller? (how to test it yourself)

In shared mode Cilium puts **every** Ingress behind one Service: **`kube-system/cilium-ingress`**. Here it is type NodePort (no cloud LB on minikube), so the Ingress `ADDRESS` column stays **empty**. That is normal; test through the Service:

```bash
k get ingressclass                                   # cilium   cilium.io/ingress-controller
k -n kube-system get svc cilium-ingress              # NodePort 80:30080, 443:30443
IP=$(k -n kube-system get svc cilium-ingress -o jsonpath='{.spec.clusterIP}')

curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' -H 'Host: shop.example.local' http://$IP   # 301 https://shop.example.local/
curl -sk --resolve shop.example.local:443:$IP https://shop.example.local                         # Q16 shop-app: hello ...
echo | openssl s_client -connect $IP:443 -servername shop.example.local 2>/dev/null | openssl x509 -noout -subject
#  subject=CN = shop.example.local, O = cks-q16      <- good

# the same via the node ports:
NIP=$(hostname -I | awk '{print $1}')
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: shop.example.local' http://$NIP:30080
```

On a cloud cluster (and probably on the exam) the Service is type LoadBalancer: use its `EXTERNAL-IP`, which also shows in `k get ing` ADDRESS. In **dedicated** mode each Ingress gets its own Service `cilium-ingress-<ingress-name>` in the Ingress's namespace.

---

## 4. Answers

<details>
<summary>Click to reveal. Try it first!</summary>

### Fast way: two imperative commands

```bash
k -n shop create secret tls shop-tls --cert=/opt/course/16/tls.crt --key=/opt/course/16/tls.key

k -n shop create ingress shop-ingress --class=cilium \
  --rule="shop.example.local/*=shop-app:80,tls=shop-tls" \
  --annotation=ingress.cilium.io/force-https=enabled

k -n shop get ing shop-ingress            # CLASS cilium, PORTS 80, 443 (ADDRESS empty here: NodePort)
k -n shop describe ing shop-ingress       # TLS: shop-tls terminates shop.example.local
```

> ⚠️ **`/*`, not `/`.** In `kubectl create ingress`, `host/path*` gives `pathType: Prefix`; `host/path` without `*` gives **`Exact`**.
> `,tls=shop-tls` adds the `tls:` block with the rule's host.

### The redirect annotation (verified on Cilium 1.20.3)

```yaml
ingress.cilium.io/force-https: enabled
```

- HTTP to the host then answers **`301 Moved Permanently`**, `Location: https://shop.example.local/` (Cilium uses **301**, not the 308 of ingress-nginx).
- `"true"` also worked in this lab, but `enabled` / `disabled` are the documented values. Use `enabled`.
- It only acts on hosts that have a **`tls:`** entry. Without TLS there is no redirect.
- `disabled` turns the redirect off for this Ingress even when the global setting is on.

### YAML way

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: shop-ingress
  namespace: shop
  annotations:
    ingress.cilium.io/force-https: enabled            # Cilium's redirect annotation (301)
spec:
  ingressClassName: cilium
  tls:
  - hosts:
    - shop.example.local                              # must match the rule host
    secretName: shop-tls                              # same namespace as the Ingress
  rules:
  - host: shop.example.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: shop-app
            port:
              number: 80
```

```bash
k -n shop create ingress shop-ingress --class=cilium --rule="shop.example.local/*=shop-app:80,tls=shop-tls" $do > ing.yaml
# add the annotation, then
k apply -f ing.yaml
```

Files: [`solution/solve.sh`](solution/solve.sh), [`solution/ingress.yaml`](solution/ingress.yaml).

### Traps (each one was verified in this lab)

| Trap | What actually happens |
|---|---|
| **`nginx.ingress.kubernetes.io/ssl-redirect: "true"`** (the Q12 habit) | **Ignored by Cilium.** HTTP answers **200**, no redirect. Grader: 7/9. Use `ingress.cilium.io/force-https: enabled`. |
| `ingressClassName: nginx` (or `--class=nginx`) | No nginx controller here, and Cilium is not the default class, so **nobody serves it**: HTTP and HTTPS both fail (`000`). Always `--class=cilium`. |
| Wrong Secret (the decoy `shop-tls-old`) | Unlike nginx, Cilium **serves that wrong cert** (`CN = old-shop.example.local`). Redirect and 200 still work, so it looks fine unless you check the cert. Grader: 7/9. |
| No `tls:` block | HTTPS fails (connection reset, no cert at all) **and** there is no redirect, even with the annotation. Grader: 5/9. |
| `tls.hosts` doesn't match the rule host | Same as no TLS for that host: HTTP 200 (no redirect), HTTPS fails. |
| Secret in another namespace | An Ingress can only use a Secret in **its own** namespace (Cilium copies it to `cilium-secrets` for Envoy itself). |
| `--rule="host/=svc:80"` | pathType **Exact**, not Prefix. Use `host/*=svc:80`. |
| `kubectl create secret generic` | Type `Opaque`. Use `create secret tls` → type `kubernetes.io/tls`, keys `tls.crt`/`tls.key`. |
| Empty `ADDRESS` in `k get ing` | Normal on minikube (NodePort). Test via `kube-system/cilium-ingress` (see section 3). |

### The global switch (why the annotation matters here)

Helm value **`ingressController.enforceHttps`** (configmap key `enforce-ingress-https`) redirects **every** TLS host. The chart default is **`true`**. This lab sets it to **`false`** so you must use the annotation. Verified: global `true` also gives **301**, and the annotation `disabled` overrides it per Ingress. On the exam, check with:

```bash
k -n kube-system get cm cilium-config -o yaml | grep -E 'enforce-ingress-https|enable-ingress-controller|ingress-default-lb-mode'
```

Even if the global is on, set the annotation: the task asks for it and it costs nothing.

</details>

---

## 5. Retry from scratch

`k -n shop delete ing shop-ingress; k -n shop delete secret shop-tls` brings you back to the start state. Or `.\cleanup.ps1` then `.\setup.ps1` (new cert each time).

## 6. Delete the node (before the next question)

```powershell
.\cleanup.ps1
```

---

## Lab notes

- Cilium is installed with Helm from your PC using [`yaml/cilium-values.yaml`](yaml/cilium-values.yaml) on `minikube start --cni=false`:
  - `kubeProxyReplacement: true` with `k8sServiceHost: control-plane.minikube.internal`, `k8sServicePort: 8443`. The ingress controller needs Cilium's own service handling to steer traffic for the ingress Service into Envoy.
  - `ingressController.enabled: true`, `loadbalancerMode: shared` (one Service `kube-system/cilium-ingress` for all Ingresses; the chart default is `dedicated`), `default: false`, `enforceHttps: false`.
  - `ingressController.service.type: NodePort` with fixed ports **30080/30443**. Its ClusterIP on 80/443 works from the node too, and the grader uses that. (`hostNetwork.enabled` was the other option; NodePort keeps the normal Service, like the exam.)
- The operator creates IngressClass `cilium` and the Service; setup waits for both.
- Setup pre-pulls the three Cilium images (agent, operator, envoy) on the node with retries, because Docker Desktop's DNS sometimes failed to resolve quay.io for several minutes.
- The grader talks to the `cilium-ingress` ClusterIP from the node: `-H Host:` for HTTP (expects 301 or 308 to `https://shop.example.local`), `--resolve` and `openssl s_client -servername` for HTTPS, and compares the served cert's SHA-256 fingerprint with `/opt/course/16/tls.crt`.

## Files

```
16-cilium-ingress/
  README.md
  setup.ps1                 node (no CNI), pre-pull, helm Cilium + ingress, node tools, certs, shop-app
  check.ps1                 grader (9 checks: Secret + Ingress spec + live 301/200/cert)
  cleanup.ps1               delete node
  setup/prepull.sh          runs on node: docker pull with retries
  setup/break-node.sh       runs on node: cert+key in /opt/course/16, decoy Secret shop-tls-old
  setup/check.sh            grader logic
  yaml/cilium-values.yaml   Helm values (KPR, ingress shared, NodePort 30080/30443, enforceHttps off)
  yaml/shop-app.yaml        namespace shop, ConfigMap page, Deployment + Service shop-app
  solution/solve.sh         imperative solution
  solution/ingress.yaml     YAML solution
```

Refs: [Cilium Kubernetes Ingress support](https://docs.cilium.io/en/stable/network/servicemesh/ingress/) · [Ingress annotations reference](https://docs.cilium.io/en/stable/network/servicemesh/ingress/#supported-ingress-annotations) · [Ingress TLS example](https://docs.cilium.io/en/stable/network/servicemesh/tls-termination/) · [kubectl create ingress](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_create/kubectl_create_ingress/)
