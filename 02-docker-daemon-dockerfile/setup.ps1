# Q02 setup: single-node minikube, insecure Docker daemon, Dockerfile + Deployment to fix.
# Run from this folder in PowerShell:  .\setup.ps1
Set-Location $PSScriptRoot

function Step($cmd) {
  & $cmd
  if ($LASTEXITCODE -ne 0) { Write-Host "FAILED (exit $LASTEXITCODE)" -ForegroundColor Red; exit 1 }
}

Step { minikube start -p cks-q02 --driver=docker --container-runtime=docker --nodes=1 --cpus=2 --memory=2048 --keep-context }
Step { minikube -p cks-q02 ssh -- mkdir -p /tmp/q02 }
Step { minikube -p cks-q02 cp setup/Dockerfile cks-q02:/tmp/q02/Dockerfile }
Step { minikube -p cks-q02 cp setup/app.sh cks-q02:/tmp/q02/app.sh }
Step { minikube -p cks-q02 cp yaml/deployment.yaml cks-q02:/tmp/q02/deployment.yaml }
Step { minikube -p cks-q02 cp setup/break-node.sh cks-q02:/tmp/q02/break-node.sh }
Step { minikube -p cks-q02 ssh -- sudo bash /tmp/q02/break-node.sh }
Step { minikube -p cks-q02 cp ../_common/node-tools.sh cks-q02:/tmp/q02/node-tools.sh }
Step { minikube -p cks-q02 ssh -- sudo bash /tmp/q02/node-tools.sh }
Step { kubectl --context cks-q02 apply -f yaml/deployment.yaml }
minikube -p cks-q02 ssh -- sudo rm -rf /tmp/q02

Write-Host ""
Write-Host "Ready. Start your timer, then:  minikube -p cks-q02 ssh --native-ssh=false" -ForegroundColor Green
