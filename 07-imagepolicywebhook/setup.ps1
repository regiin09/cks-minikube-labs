# Q07 setup: single node, image scanner (HTTPS ImagePolicyWebhook backend) running on
# the node, INCOMPLETE config in /etc/kubernetes/epconfig, test resource in /root/q07.
# Run from this folder in PowerShell:  .\setup.ps1
Set-Location $PSScriptRoot
$P = "cks-q07"

function Step($cmd) {
  & $cmd
  if ($LASTEXITCODE -ne 0) { Write-Host "FAILED (exit $LASTEXITCODE)" -ForegroundColor Red; exit 1 }
}

Step { minikube start -p $P --driver=docker --container-runtime=docker --nodes=1 --cpus=2 --memory=2048 --keep-context }
Step { minikube -p $P ssh -- mkdir -p /tmp/q07 }
Step { minikube -p $P cp setup/image-scanner.py "${P}:/tmp/q07/image-scanner.py" }
Step { minikube -p $P cp setup/break-node.sh "${P}:/tmp/q07/break-node.sh" }
Step { minikube -p $P cp yaml/vulnerable-resource.yml "${P}:/tmp/q07/vulnerable-resource.yml" }
Step { minikube -p $P cp ../_common/node-tools.sh "${P}:/tmp/q07/node-tools.sh" }
Step { minikube -p $P ssh -- sudo bash /tmp/q07/break-node.sh }
Step { minikube -p $P ssh -- sudo bash /tmp/q07/node-tools.sh }
minikube -p $P ssh -- sudo rm -rf /tmp/q07

Write-Host ""
Write-Host "Ready. Start your timer, then:  minikube -p $P ssh --native-ssh=false" -ForegroundColor Green
