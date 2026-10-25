# Q16 setup: single node, Cilium 1.20.3 (helm) with the Cilium Ingress controller
# (IngressClass "cilium", shared mode, NodePort 30080/30443), namespace shop with
# Deployment + Service shop-app (HTTP 80), cert + key in /opt/course/16.
# Needs helm on your machine.
# Run from this folder in PowerShell:  .\setup.ps1
Set-Location $PSScriptRoot
$P = "cks-q16"

function Step($cmd) {
  & $cmd
  if ($LASTEXITCODE -ne 0) { Write-Host "FAILED (exit $LASTEXITCODE)" -ForegroundColor Red; exit 1 }
}

Step { minikube start -p $P --driver=docker --container-runtime=docker --nodes=1 --cpus=2 --memory=2048 --cni=false --keep-context }

helm repo add cilium https://helm.cilium.io *> $null
helm repo update cilium *> $null

Write-Host ">> pre-pulling Cilium images on the node (retries if quay.io is flaky)"
$imgs = helm template cilium cilium/cilium --version 1.20.3 -n kube-system -f yaml/cilium-values.yaml |
  Select-String '^\s*image: "(.+)"' | ForEach-Object { $_.Matches[0].Groups[1].Value } | Sort-Object -Unique
Step { minikube -p $P cp setup/prepull.sh "${P}:/tmp/prepull.sh" }
Step { minikube -p $P ssh -- sudo bash /tmp/prepull.sh @imgs }
minikube -p $P ssh -- sudo rm -f /tmp/prepull.sh

Write-Host ">> installing Cilium + ingress controller (helm) - takes ~2-3 min"
Step { helm --kube-context $P upgrade --install cilium cilium/cilium --version 1.20.3 -n kube-system -f yaml/cilium-values.yaml }
Step { kubectl --context $P -n kube-system rollout status ds/cilium --timeout=600s }
Step { kubectl --context $P -n kube-system rollout status ds/cilium-envoy --timeout=300s }
Step { kubectl --context $P -n kube-system rollout status deploy/cilium-operator --timeout=300s }

# pods that started before Cilium got minikube's bridge IPs; recreate them on Cilium
kubectl --context $P -n kube-system rollout restart deploy/coredns | Out-Null
Step { kubectl --context $P -n kube-system rollout status deploy/coredns --timeout=180s }

Step { minikube -p $P cp ../_common/node-tools.sh "${P}:/tmp/node-tools.sh" }
Step { minikube -p $P ssh -- sudo bash /tmp/node-tools.sh }
Step { minikube -p $P cp setup/break-node.sh "${P}:/tmp/break-node.sh" }
Step { minikube -p $P ssh -- sudo -i bash /tmp/break-node.sh }
minikube -p $P ssh -- sudo rm -f /tmp/node-tools.sh /tmp/break-node.sh

Step { kubectl --context $P apply -f yaml/shop-app.yaml }
Step { kubectl --context $P -n shop rollout status deploy/shop-app --timeout=180s }

# the operator creates IngressClass "cilium" and the shared Service kube-system/cilium-ingress
for ($i = 0; $i -lt 30; $i++) {
  kubectl --context $P get ingressclass cilium *> $null
  if ($LASTEXITCODE -eq 0) { kubectl --context $P -n kube-system get svc cilium-ingress *> $null }
  if ($LASTEXITCODE -eq 0) { break }
  Start-Sleep -Seconds 5
}
Step { kubectl --context $P get ingressclass cilium }
Step { kubectl --context $P -n kube-system get svc cilium-ingress }

Write-Host ""
Write-Host "Ready. Start your timer, then:  minikube -p $P ssh --native-ssh=false" -ForegroundColor Green
