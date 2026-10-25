# Q09 setup: single node, cert + key in /opt/course/09, Deployment "web" in namespace "secure"
# that mounts a TLS Secret which does not exist yet (random name each run) -> ContainerCreating.
# Run from this folder in PowerShell:  .\setup.ps1
Set-Location $PSScriptRoot
$P = "cks-q09"

function Step($cmd) {
  & $cmd
  if ($LASTEXITCODE -ne 0) { Write-Host "FAILED (exit $LASTEXITCODE)" -ForegroundColor Red; exit 1 }
}

Step { minikube start -p $P --driver=docker --container-runtime=docker --nodes=1 --cpus=2 --memory=2048 --keep-context }
Step { minikube -p $P ssh -- mkdir -p /tmp/q09 }
Step { minikube -p $P cp ../_common/node-tools.sh "${P}:/tmp/q09/node-tools.sh" }
Step { minikube -p $P ssh -- sudo bash /tmp/q09/node-tools.sh }
Step { minikube -p $P cp yaml/web.yaml "${P}:/tmp/q09/web.yaml" }
Step { minikube -p $P cp setup/break-node.sh "${P}:/tmp/q09/break-node.sh" }
Step { minikube -p $P ssh -- sudo bash /tmp/q09/break-node.sh }
minikube -p $P ssh -- sudo rm -rf /tmp/q09

kubectl --context $P -n secure get deploy,pod,svc

Write-Host ""
Write-Host "Ready. Start your timer, then:  minikube -p $P ssh --native-ssh=false" -ForegroundColor Green
