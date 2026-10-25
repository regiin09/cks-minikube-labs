# Q06 setup: single node, Cilium 1.20.3 (helm) with SPIRE mutual auth, cilium CLI on
# the node, workloads in payments / checkout / marketing. No policies yet.
# Needs helm on your machine.
# Run from this folder in PowerShell:  .\setup.ps1
Set-Location $PSScriptRoot
$P = "cks-q06"

function Step($cmd) {
  & $cmd
  if ($LASTEXITCODE -ne 0) { Write-Host "FAILED (exit $LASTEXITCODE)" -ForegroundColor Red; exit 1 }
}

Step { minikube start -p $P --driver=docker --container-runtime=docker --nodes=1 --cpus=3 --memory=3072 --cni=false --keep-context }

Write-Host ">> installing Cilium + SPIRE (helm) - takes ~3 min"
helm repo add cilium https://helm.cilium.io *> $null
helm repo update cilium *> $null
Step { helm --kube-context $P upgrade --install cilium cilium/cilium --version 1.20.3 -n kube-system -f yaml/cilium-values.yaml }
Step { kubectl --context $P -n kube-system rollout status ds/cilium --timeout=400s }

# pods that started before Cilium got minikube's bridge IPs; recreate them on Cilium
kubectl --context $P -n kube-system rollout restart deploy/coredns | Out-Null
kubectl --context $P -n cilium-spire delete pod --all --wait=false | Out-Null
Start-Sleep -Seconds 10
Step { kubectl --context $P -n cilium-spire wait --for=condition=ready pod --all --timeout=300s }
Step { kubectl --context $P -n kube-system rollout status deploy/coredns --timeout=120s }

Step { minikube -p $P cp ../_common/node-tools.sh "${P}:/tmp/node-tools.sh" }
Step { minikube -p $P ssh -- sudo bash /tmp/node-tools.sh }
Step { minikube -p $P cp setup/node.sh "${P}:/tmp/node.sh" }
Step { minikube -p $P ssh -- sudo bash /tmp/node.sh }
minikube -p $P ssh -- sudo rm -f /tmp/node-tools.sh /tmp/node.sh

Step { kubectl --context $P apply -f yaml/workloads.yaml }
foreach ($ns in "payments", "checkout", "marketing") {
  Step { kubectl --context $P -n $ns wait --for=condition=available deploy --all --timeout=240s }
}

Write-Host ""
Write-Host "Ready. Start your timer, then:  minikube -p $P ssh --native-ssh=false" -ForegroundColor Green
