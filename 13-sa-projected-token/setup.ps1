# Q13 setup: single node, namespace monitoring, ServiceAccount stats-monitor-sa (automount on,
# the default) and Deployment stats-monitor using it. Manifest at /opt/course/13/deployment.yaml.
# Run from this folder in PowerShell:  .\setup.ps1
Set-Location $PSScriptRoot
$P = "cks-q13"

function Step($cmd) {
  & $cmd
  if ($LASTEXITCODE -ne 0) { Write-Host "FAILED (exit $LASTEXITCODE)" -ForegroundColor Red; exit 1 }
}

Step { minikube start -p $P --driver=docker --container-runtime=docker --nodes=1 --cpus=2 --memory=2048 --keep-context }
Step { minikube -p $P ssh -- mkdir -p /tmp/q13 }
Step { minikube -p $P cp yaml/deployment.yaml "${P}:/tmp/q13/deployment.yaml" }
Step { minikube -p $P cp setup/break-node.sh "${P}:/tmp/q13/break-node.sh" }
Step { minikube -p $P ssh -- sudo bash /tmp/q13/break-node.sh }
Step { minikube -p $P cp ../_common/node-tools.sh "${P}:/tmp/q13/node-tools.sh" }
Step { minikube -p $P ssh -- sudo bash /tmp/q13/node-tools.sh }
minikube -p $P ssh -- sudo rm -rf /tmp/q13
Step { kubectl --context $P apply -f yaml/serviceaccount.yaml }
Step { kubectl --context $P apply -f yaml/deployment.yaml }
Step { kubectl --context $P -n monitoring rollout status deploy/stats-monitor --timeout=180s }

Write-Host ""
Write-Host "Ready. Start your timer, then:  minikube -p $P ssh --native-ssh=false" -ForegroundColor Green
