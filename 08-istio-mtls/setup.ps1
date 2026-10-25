# Q08 setup: single node, Istio (istioctl, minimal profile) installed, istioctl on the node,
# Deployment web in namespace shop WITHOUT sidecars, plaintext client in namespace legacy.
# Run from this folder in PowerShell:  .\setup.ps1
Set-Location $PSScriptRoot
$P = "cks-q08"

function Step($cmd) {
  & $cmd
  if ($LASTEXITCODE -ne 0) { Write-Host "FAILED (exit $LASTEXITCODE)" -ForegroundColor Red; exit 1 }
}

Step { minikube start -p $P --driver=docker --container-runtime=docker --nodes=1 --cpus=2 --memory=3072 --keep-context }
Step { minikube -p $P ssh -- mkdir -p /tmp/q08 }
Step { minikube -p $P cp ../_common/node-tools.sh "${P}:/tmp/q08/node-tools.sh" }
Step { minikube -p $P ssh -- sudo bash /tmp/q08/node-tools.sh }
Step { minikube -p $P cp setup/node.sh "${P}:/tmp/q08/node.sh" }
Step { minikube -p $P ssh -- sudo bash /tmp/q08/node.sh }
minikube -p $P ssh -- sudo rm -rf /tmp/q08

Step { kubectl --context $P apply -f yaml/workloads.yaml }
Step { kubectl --context $P -n shop wait --for=condition=available deploy --all --timeout=180s }
Step { kubectl --context $P -n legacy wait --for=condition=available deploy --all --timeout=180s }

Write-Host ""
Write-Host "Ready. Start your timer, then:  minikube -p $P ssh --native-ssh=false" -ForegroundColor Green
