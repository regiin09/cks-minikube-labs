#!/usr/bin/env bash
# SOLUTION (run as root on the node). Same steps as the README answers.
kubectl -n shop create secret tls shop-tls \
  --cert=/opt/course/16/tls.crt --key=/opt/course/16/tls.key

kubectl -n shop create ingress shop-ingress --class=cilium \
  --rule="shop.example.local/*=shop-app:80,tls=shop-tls" \
  --annotation=ingress.cilium.io/force-https=enabled

kubectl -n shop get ingress shop-ingress
