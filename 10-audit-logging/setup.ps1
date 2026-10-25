# Q10 setup: single node, basic audit policy at /etc/kubernetes/logpolicy/sample-policy.yaml,
# auditing NOT enabled in the kube-apiserver, namespace "web".
# Run from this folder in PowerShell:  .\setup.ps1
Set-Location $PSScriptRoot
$P = "cks-q10"

function Step($cmd) {
  & $cmd
  if ($LASTEXITCODE -ne 0) { Write-Host "FAILED (exit $LASTEXITCODE)" -ForegroundColor Red; exit 1 }
}

Step { minikube start -p $P --driver=docker --container-runtime=docker --nodes=1 --cpus=2 --memory=2048 --keep-context }
Step { minikube -p $P ssh -- mkdir -p /tmp/q10 }
Step { minikube -p $P cp yaml/sample-policy.yaml "${P}:/tmp/q10/sample-policy.yaml" }
Step { minikube -p $P cp setup/break-node.sh "${P}:/tmp/q10/break-node.sh" }
Step { minikube -p $P cp ../_common/node-tools.sh "${P}:/tmp/q10/node-tools.sh" }
Step { minikube -p $P ssh -- sudo bash /tmp/q10/break-node.sh }
Step { minikube -p $P ssh -- sudo bash /tmp/q10/node-tools.sh }
minikube -p $P ssh -- sudo rm -rf /tmp/q10

Write-Host ""
Write-Host "Ready. Start your timer, then:  minikube -p $P ssh --native-ssh=false" -ForegroundColor Green
