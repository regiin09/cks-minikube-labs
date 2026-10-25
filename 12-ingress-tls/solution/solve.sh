#!/usr/bin/env bash
# SOLUTION (run as root on the node). Same steps as the README answers.
kubectl -n web create secret tls secure-tls \
  --cert=/opt/course/12/tls.crt --key=/opt/course/12/tls.key

kubectl -n web create ingress secure-ingress --class=nginx \
  --rule="secure.example.local/*=web-app:80,tls=secure-tls" \
  --annotation=nginx.ingress.kubernetes.io/ssl-redirect=true

kubectl -n web get ingress secure-ingress
