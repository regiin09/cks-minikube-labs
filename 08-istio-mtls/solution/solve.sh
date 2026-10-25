#!/usr/bin/env bash
# SOLUTION (run as root on the node). Same steps as the README answers.

# 1. put namespace shop in the mesh
kubectl label namespace shop istio-injection=enabled --overwrite

# 2. the label only affects NEW pods: recreate the existing ones
kubectl -n shop rollout restart deploy web
kubectl -n shop rollout status deploy web
kubectl -n shop get pods            # READY 2/2

# 3. STRICT mTLS for the whole namespace
kubectl apply -f - <<'YAML'
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: default
  namespace: shop
spec:
  mtls:
    mode: STRICT
YAML
kubectl -n shop get peerauthentication
