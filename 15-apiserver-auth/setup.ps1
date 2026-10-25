# Q15 setup: single node, kube-apiserver open to anonymous users (anonymous-auth=true,
# AlwaysAllow, no NodeRestriction) + ClusterRoleBinding system:anonymous -> cluster-admin.
# Run from this folder in PowerShell:  .\setup.ps1
Set-Location $PSScriptRoot
$P = "cks-q15"

function Step($cmd) {
  & $cmd
  if ($LASTEXITCODE -ne 0) { Write-Host "FAILED (exit $LASTEXITCODE)" -ForegroundColor Red; exit 1 }
}

Step { minikube start -p $P --driver=docker --container-runtime=docker --nodes=1 --cpus=2 --memory=2048 --keep-context }
Step { minikube -p $P ssh -- mkdir -p /tmp/q15 }
Step { minikube -p $P cp setup/break-node.sh "${P}:/tmp/q15/break-node.sh" }
Step { minikube -p $P cp yaml/crb-system-anonymous.yaml "${P}:/tmp/q15/crb-system-anonymous.yaml" }
Step { minikube -p $P cp ../_common/node-tools.sh "${P}:/tmp/q15/node-tools.sh" }
Step { minikube -p $P ssh -- sudo bash /tmp/q15/break-node.sh }
Step { minikube -p $P ssh -- sudo bash /tmp/q15/node-tools.sh }
minikube -p $P ssh -- sudo rm -rf /tmp/q15

Write-Host ""
Write-Host "Ready. Start your timer, then:  minikube -p $P ssh --native-ssh=false" -ForegroundColor Green
