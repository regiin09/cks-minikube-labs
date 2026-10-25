#!/usr/bin/env bash
# SOLUTION (run as root on the node). Same as the README answers.
A=$(grep -o 'allow-from-[a-z0-9-]*' /opt/course/11/task.txt | head -n1 | sed 's/allow-from-//')
kubectl apply -f - <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: deny-all-ingress, namespace: prod}
spec:
  podSelector: {}
  policyTypes: [Ingress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: allow-from-$A, namespace: prod}
spec:
  podSelector: {}
  policyTypes: [Ingress]
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: $A
YAML
kubectl -n prod get netpol
