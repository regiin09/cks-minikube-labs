# Q01 setup: creates the single-node minikube cluster and breaks kubelet + etcd.
# Run from this folder in PowerShell:  .\setup.ps1
Set-Location $PSScriptRoot

function Step($cmd) {
  & $cmd
  if ($LASTEXITCODE -ne 0) { Write-Host "FAILED (exit $LASTEXITCODE)" -ForegroundColor Red; exit 1 }
}

Step { minikube start -p cks-q01 --driver=docker --container-runtime=docker --nodes=1 --cpus=2 --memory=2048 --keep-context }
Step { minikube -p cks-q01 cp setup/break-node.sh cks-q01:/tmp/break-node.sh }
Step { minikube -p cks-q01 ssh -- sudo bash /tmp/break-node.sh }
Step { minikube -p cks-q01 cp ../_common/node-tools.sh cks-q01:/tmp/node-tools.sh }
Step { minikube -p cks-q01 ssh -- sudo bash /tmp/node-tools.sh }

Write-Host ""
Write-Host "Ready. Start your timer, then:  minikube -p cks-q01 ssh --native-ssh=false" -ForegroundColor Green
