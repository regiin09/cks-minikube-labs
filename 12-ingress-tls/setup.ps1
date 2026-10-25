# Q12 setup: single node, ingress-nginx (minikube addon, IngressClass "nginx"),
# namespace web with Deployment + Service web-app (HTTP 80), cert + key in /opt/course/12.
# Run from this folder in PowerShell:  .\setup.ps1
Set-Location $PSScriptRoot
$P = "cks-q12"

function Step($cmd) {
  & $cmd
  if ($LASTEXITCODE -ne 0) { Write-Host "FAILED (exit $LASTEXITCODE)" -ForegroundColor Red; exit 1 }
}

Step { minikube start -p $P --driver=docker --container-runtime=docker --nodes=1 --cpus=2 --memory=2048 --keep-context }

Write-Host ">> enabling ingress-nginx addon - takes ~1-2 min"
Step { minikube -p $P addons enable ingress }
# the admission webhook must be up before any Ingress can be created
Step { kubectl --context $P -n ingress-nginx wait --for=condition=complete job --all --timeout=300s }
Step { kubectl --context $P -n ingress-nginx wait --for=condition=ready pod -l app.kubernetes.io/component=controller --timeout=300s }

Step { minikube -p $P cp ../_common/node-tools.sh "${P}:/tmp/node-tools.sh" }
Step { minikube -p $P ssh -- sudo bash /tmp/node-tools.sh }
Step { minikube -p $P cp setup/break-node.sh "${P}:/tmp/break-node.sh" }
Step { minikube -p $P ssh -- sudo -i bash /tmp/break-node.sh }
minikube -p $P ssh -- sudo rm -f /tmp/node-tools.sh /tmp/break-node.sh

Step { kubectl --context $P apply -f yaml/web-app.yaml }
Step { kubectl --context $P -n web rollout status deploy/web-app --timeout=180s }

Write-Host ""
Write-Host "Ready. Start your timer, then:  minikube -p $P ssh --native-ssh=false" -ForegroundColor Green
